-- ============================================================================
-- Kairo · 08_subscriptions.sql
-- Verdade da assinatura Premium (espelho do Stripe). Escrita EXCLUSIVAMENTE
-- pelo webhook via service role; client só lê a própria linha (RLS).
--
-- Princípios (ver docs/00-visao-arquitetura.md §5 e docs/03-stripe-billing.md):
--   • subscriptions é canônica: o webhook resolve o estado real na Stripe e
--     faz UPSERT atômico. Sem read-modify-write.
--   • stripe_events serve como ledger de idempotência: INSERT ON CONFLICT
--     DO NOTHING — evento já visto não reprocessa.
--   • Nenhuma policy de write em subscriptions: service role bypassa RLS;
--     client sem policy = sem caminho para se autoconceder Premium.
--   • is_premium() (definida em 07_uso_ia.sql) já está alinhada aos status
--     usados aqui (active, trialing); esta migração apenas reafirma a
--     definição com a mesma semântica, agora que a tabela existe — antes
--     o EXCEPTION undefined_table cobria o pré-Fase 03.
-- ============================================================================

-- ── Tabela subscriptions ────────────────────────────────────────────────────
-- 1 linha por usuário (user_id é PK). Status segue exatamente o vocabulário
-- da Stripe — `none` é estado inicial antes de qualquer Checkout.
create table if not exists public.subscriptions (
  user_id                 uuid        primary key references auth.users(id) on delete cascade,
  stripe_customer_id      text        unique,
  stripe_subscription_id  text,
  status                  text        not null default 'none'
    check (status in ('none','incomplete','incomplete_expired','trialing','active','past_due','canceled','unpaid','paused')),
  price_id                text,
  current_period_end      timestamptz,
  cancel_at_period_end    boolean     not null default false,
  updated_at              timestamptz not null default now()
);

-- Lookups quentes do webhook: por customer (resolver user_id na chegada de
-- evento) e por subscription (re-fetch / log).
create index if not exists subscriptions_stripe_customer_idx
  on public.subscriptions (stripe_customer_id);
create index if not exists subscriptions_stripe_subscription_idx
  on public.subscriptions (stripe_subscription_id);

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Apenas SELECT da própria linha. NENHUMA policy de insert/update/delete:
-- a escrita é EXCLUSIVA do webhook via service role. É essa ausência de
-- policy de write que impede o client de se autoconceder Premium.
alter table public.subscriptions enable row level security;

drop policy if exists "subscriptions_select_own" on public.subscriptions;
create policy "subscriptions_select_own"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- ── Tabela stripe_events ────────────────────────────────────────────────────
-- Ledger de idempotência. id = event.id da Stripe; PK natural rejeita o
-- segundo INSERT do mesmo evento. Sem policies → tabela invisível ao client.
create table if not exists public.stripe_events (
  id           text        primary key,
  type         text        not null,
  received_at  timestamptz not null default now()
);

alter table public.stripe_events enable row level security;
-- Intencionalmente: NENHUMA policy. RLS habilitado sem policy = ninguém via
-- API/anon/auth role consegue ler/escrever. Service role bypassa.

-- ── Realinhamento de is_premium() ───────────────────────────────────────────
-- A função foi criada em 07_uso_ia.sql com proteção contra "relation does not
-- exist". Agora que a tabela existe, recriamos sem o EXCEPTION para usar a
-- forma SQL simples (mais eficiente) e com search_path explícito. A semântica
-- é a mesma: premium = status in ('active','trialing') AND current_period_end
-- > now(). Demais status (past_due/canceled/incomplete/unpaid/paused/none)
-- explicitamente NÃO concedem premium — past_due cobre janela de retry de
-- cobrança onde o usuário não pagou ainda.
create or replace function public.is_premium(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.subscriptions s
    where s.user_id = uid
      and s.status in ('active','trialing')
      and s.current_period_end > now()
  );
$$;

grant execute on function public.is_premium(uuid) to authenticated, service_role;
