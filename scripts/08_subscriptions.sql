-- ============================================================================
-- Kairo · 08_subscriptions.sql
-- Entitlement Premium CANÔNICO e AGNÓSTICO DE PROVIDER (Stripe web + Apple IAP
-- + Google Play). Uma linha por usuário, escrita EXCLUSIVAMENTE pelos webhooks
-- via service role; o client só lê a própria linha (RLS).
--
-- Este arquivo SUBSTITUI a versão Stripe-only descrita no doc 03. As migrações
-- abaixo são idempotentes e tolerantes a um banco que já rodou a versão antiga
-- (renomeia/adiciona colunas em vez de exigir banco limpo).
--
-- Princípios (ver docs/00-visao-arquitetura.md §5 e docs/07-billing-multiplataforma.md):
--   • subscriptions é canônica: cada webhook RE-BUSCA o estado real no provider
--     e chama aplicar_estado_assinatura() (UPSERT atômico, sem read-modify-write).
--   • billing_events é o ledger de idempotência de TODOS os providers:
--     PK (provider, event_id); INSERT ON CONFLICT DO NOTHING rejeita reprocesso.
--   • Convergência multiplataforma: um provider só pode REBAIXAR o entitlement
--     se for o MESMO que concede o acesso vigente — a expiração de uma Apple
--     não apaga uma Stripe ainda ativa (regra centralizada na RPC).
--   • Nenhuma policy de write: service role bypassa RLS; client sem policy de
--     escrita = sem caminho para se autoconceder Premium.
-- ============================================================================

-- ── Tabela subscriptions (entitlement canônico, 1 linha/usuário) ─────────────
-- Para bancos novos: cria já no formato agnóstico de provider.
create table if not exists public.subscriptions (
  user_id                 uuid        primary key references auth.users(id) on delete cascade,
  provider                text        not null default 'none',   -- none|stripe|apple|google
  status                  text        not null default 'none',   -- none|active|trialing|past_due|canceled|expired|grace|incomplete
  product_id              text,                                  -- price/produto que concedeu o acesso
  current_period_end      timestamptz,
  cancel_at_period_end    boolean     not null default false,
  stripe_customer_id      text        unique,                    -- só Stripe
  provider_sub_id         text,                                  -- stripe sub id | apple original_transaction_id | google purchaseToken
  updated_at              timestamptz not null default now()
);

-- ── Migração de bancos que rodaram a versão Stripe-only ──────────────────────
-- A versão antiga tinha: stripe_subscription_id, price_id, status com CHECK
-- restrito (sem 'grace'/'expired') e SEM coluna provider/product_id/provider_sub_id.
-- Adicionamos o que falta e portamos os dados, sem perder linhas existentes.
alter table public.subscriptions
  add column if not exists provider             text        not null default 'none',
  add column if not exists product_id           text,
  add column if not exists provider_sub_id      text,
  add column if not exists current_period_end   timestamptz,
  add column if not exists cancel_at_period_end  boolean    not null default false;

do $$
begin
  -- Porta price_id -> product_id (mesma semântica: o que concedeu o acesso).
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='subscriptions' and column_name='price_id'
  ) then
    update public.subscriptions set product_id = price_id where product_id is null and price_id is not null;
    alter table public.subscriptions drop column price_id;
  end if;

  -- Porta stripe_subscription_id -> provider_sub_id e marca provider='stripe'
  -- nas linhas que já tinham assinatura Stripe.
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='subscriptions' and column_name='stripe_subscription_id'
  ) then
    update public.subscriptions
       set provider_sub_id = stripe_subscription_id,
           provider        = case when provider = 'none' and stripe_subscription_id is not null then 'stripe' else provider end
     where provider_sub_id is null and stripe_subscription_id is not null;
    -- onde só existe customer (status 'none', sem sub), assume canal Stripe.
    update public.subscriptions
       set provider = 'stripe'
     where provider = 'none' and stripe_customer_id is not null;
    alter table public.subscriptions drop column stripe_subscription_id;
  end if;
end $$;

-- O CHECK antigo (subscriptions_status_check) não conhece 'grace'/'expired';
-- removemos para o novo vocabulário. Não reimpomos CHECK rígido: o conjunto de
-- status é controlado pelos webhooks (mapeamento explícito em cada um).
alter table public.subscriptions drop constraint if exists subscriptions_status_check;

-- ── Índices ──────────────────────────────────────────────────────────────────
-- Lookups quentes dos webhooks: por customer (Stripe) e por (provider, sub_id)
-- (fallback de identidade quando o appAccountToken/obfuscatedAccountId falha).
create index if not exists subscriptions_stripe_customer_idx
  on public.subscriptions (stripe_customer_id);
create index if not exists subscriptions_provider_sub_idx
  on public.subscriptions (provider, provider_sub_id);
-- Índice legado da versão antiga (stripe_subscription_id) já não se aplica.
drop index if exists public.subscriptions_stripe_subscription_idx;

-- ── RLS em subscriptions ─────────────────────────────────────────────────────
-- Apenas SELECT da própria linha. NENHUMA policy de insert/update/delete:
-- a escrita é EXCLUSIVA dos webhooks via service role (bypassa RLS).
alter table public.subscriptions enable row level security;

drop policy if exists "subscriptions_select_own" on public.subscriptions;
create policy "subscriptions_select_own"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- ── Tabela billing_events (dedupe de webhook — todos os providers) ────────────
-- PK natural (provider, event_id) rejeita o 2º INSERT do mesmo evento:
--   Stripe   -> event.id
--   Apple    -> notificationUUID
--   Google   -> message.messageId
-- Sem policies → invisível ao client; só service role escreve.
create table if not exists public.billing_events (
  provider     text        not null,
  event_id     text        not null,
  type         text        not null,
  received_at  timestamptz not null default now(),
  primary key (provider, event_id)
);

alter table public.billing_events enable row level security;
-- Intencionalmente: NENHUMA policy. RLS habilitado sem policy = ninguém via
-- API/anon/auth role lê ou escreve. Service role bypassa.

-- A tabela stripe_events (versão antiga, Stripe-only) foi SUPERADA por
-- billing_events. É inofensiva se permanecer, mas já não é escrita por ninguém;
-- pode ser removida manualmente: drop table if exists public.stripe_events;

-- ── Função canônica de gating: is_premium(uid) ───────────────────────────────
-- premium = status in ('active','trialing','grace') AND current_period_end > now().
-- 'grace' (Apple billing-retry / Google grace period) MANTÉM o acesso enquanto
-- a loja tenta recobrar o pagamento — não rebaixa o usuário no meio da janela.
-- Recriada como SQL puro (mais eficiente); a proteção contra undefined_table do
-- 07_uso_ia.sql não é mais necessária pois a tabela já existe acima.
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
      and s.status in ('active','trialing','grace')
      and s.current_period_end > now()
  );
$$;

grant execute on function public.is_premium(uuid) to authenticated, service_role;

-- ── RPC de convergência: aplicar_estado_assinatura() ─────────────────────────
-- Chamada pelos 3 webhooks (e por verify-purchase) com o estado JÁ re-buscado
-- no provider. Faz UPSERT atômico por linha (lock implícito do ON CONFLICT),
-- aplicando a regra de convergência multiplataforma SEM read-modify-write:
--
--   Sobrescreve a linha existente SOMENTE quando UMA condição vale:
--     (a) o novo estado CONCEDE acesso (p_status in active|trialing|grace), OU
--     (b) a linha atual pertence ao MESMO provider que está escrevendo.
--   Caso contrário (rebaixamento vindo de um provider DIFERENTE do que concede
--   o acesso vigente) → o DO UPDATE não casa o WHERE = no-op; a linha continua
--   existindo intacta. Assim um EXPIRED da Apple não apaga uma Stripe ativa.
--
-- stripe_customer_id é preservado via COALESCE: webhooks não-Stripe passam NULL
-- e não devem apagar a vinculação Stripe já registrada (coluna UNIQUE).
create or replace function public.aplicar_estado_assinatura(
  p_user_id               uuid,
  p_provider              text,
  p_status                text,
  p_product_id            text,
  p_current_period_end    timestamptz,
  p_cancel_at_period_end  boolean,
  p_stripe_customer_id    text,
  p_provider_sub_id       text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.subscriptions as s (
    user_id, provider, status, product_id, current_period_end,
    cancel_at_period_end, stripe_customer_id, provider_sub_id, updated_at
  )
  values (
    p_user_id, p_provider, p_status, p_product_id, p_current_period_end,
    coalesce(p_cancel_at_period_end, false), p_stripe_customer_id, p_provider_sub_id, now()
  )
  on conflict (user_id) do update set
    provider             = excluded.provider,
    status               = excluded.status,
    product_id           = excluded.product_id,
    current_period_end   = excluded.current_period_end,
    cancel_at_period_end = excluded.cancel_at_period_end,
    stripe_customer_id   = coalesce(excluded.stripe_customer_id, s.stripe_customer_id),
    provider_sub_id      = excluded.provider_sub_id,
    updated_at           = now()
  where excluded.status in ('active','trialing','grace')
     or s.provider = excluded.provider;
$$;

grant execute on function public.aplicar_estado_assinatura(
  uuid, text, text, text, timestamptz, boolean, text, text
) to service_role;
