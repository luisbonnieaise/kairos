-- ============================================================================
-- Kairo · 12_billing_multiplataforma.sql
-- Migra a assinatura de "espelho do Stripe" (doc 03) para um entitlement
-- ÚNICO e AGNÓSTICO de provider (doc 07): Stripe (web) + Apple IAP + Google Play.
--
-- Princípios (ver docs/07-billing-multiplataforma.md §2 e docs/00 §5):
--   • subscriptions continua canônica: 1 linha por usuário, escrita SÓ por
--     service role (webhooks/verify-purchase). Client só lê a própria linha.
--   • Toda escrita passa por aplicar_estado_assinatura() — UPSERT atômico com
--     a regra de convergência multiplataforma (um provider não apaga o acesso
--     concedido por outro).
--   • Idempotência unificada em billing_events (provider, event_id).
--   • is_premium() ganha 'grace' (janela de retry de cobrança ainda dá acesso).
--
-- Migração ADITIVA: não dropa subscriptions nem stripe_events (back-compat);
-- apenas estende. Pode rodar em produção com dados Stripe existentes.
-- ============================================================================

-- ── 1. Estende subscriptions para ser agnóstica de provider ─────────────────
alter table public.subscriptions
  add column if not exists provider        text not null default 'none',
  add column if not exists product_id      text,
  add column if not exists provider_sub_id text;

-- Backfill das linhas Stripe pré-existentes (price_id/stripe_subscription_id
-- são as colunas antigas do doc 03; ficam para trás-compat, não as removo aqui).
update public.subscriptions
set provider        = 'stripe',
    product_id      = coalesce(product_id, price_id),
    provider_sub_id = coalesce(provider_sub_id, stripe_subscription_id)
where stripe_customer_id is not null
  and provider = 'none';

-- Vocabulário de provider.
alter table public.subscriptions
  drop constraint if exists subscriptions_provider_check;
alter table public.subscriptions
  add constraint subscriptions_provider_check
  check (provider in ('none','stripe','apple','google'));

-- Status agora cobre o vocabulário cross-provider. 'grace' = billing retry
-- (ainda concede acesso); 'expired' = ciclo terminou sem renovar.
alter table public.subscriptions
  drop constraint if exists subscriptions_status_check;
alter table public.subscriptions
  add constraint subscriptions_status_check
  check (status in (
    'none','incomplete','incomplete_expired','trialing','active',
    'past_due','canceled','unpaid','paused','grace','expired'
  ));

-- Lookup quente dos webhooks Apple/Google: resolver a linha por provider_sub_id
-- (apple original_transaction_id | google purchaseToken).
create index if not exists subscriptions_provider_sub_idx
  on public.subscriptions (provider, provider_sub_id);

-- ── 2. billing_events: dedupe unificado dos 3 providers ─────────────────────
-- PK natural (provider, event_id) rejeita o reprocessamento do mesmo evento.
-- event_id = event.id (Stripe) | notificationUUID (Apple) | messageId (Google).
create table if not exists public.billing_events (
  provider     text        not null,
  event_id     text        not null,
  type         text        not null,
  received_at  timestamptz not null default now(),
  primary key (provider, event_id)
);

alter table public.billing_events enable row level security;
-- Intencionalmente SEM policy: RLS on sem policy = invisível a anon/auth.
-- Só service role (que bypassa RLS) escreve/lê.

-- ── 3. is_premium(): acrescenta 'grace' ─────────────────────────────────────
-- Mantém paridade EXATA com lib/core/billing.dart::derivarPremium.
-- premium = status in ('active','trialing','grace') AND current_period_end > now().
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

-- ── 4. aplicar_estado_assinatura(): UPSERT canônico + convergência ──────────
-- Chamada por TODOS os caminhos de escrita (stripe-webhook, apple-webhook,
-- google-webhook, verify-purchase). SECURITY DEFINER + grant só p/ service_role
-- => client nunca chama isto direto.
--
-- Regra de convergência multiplataforma (doc 07 §2): um provider só pode
-- REBAIXAR o entitlement (gravar status que NÃO concede acesso) se ele for o
-- MESMO provider que concede o acesso vigente. Assim a expiração de uma Apple
-- não apaga uma Stripe ainda ativa. Estados que CONCEDEM acesso
-- (active|trialing|grace) sempre aplicam (o usuário pagou de fato).
create or replace function public.aplicar_estado_assinatura(
  p_user_id              uuid,
  p_provider             text,
  p_status               text,
  p_product_id           text,
  p_current_period_end   timestamptz,
  p_cancel_at_period_end boolean default false,
  p_provider_sub_id      text default null
)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existente public.subscriptions;
  v_concede   boolean := p_status in ('active','trialing','grace');
  v_resultado public.subscriptions;
begin
  if p_user_id is null then
    raise exception 'aplicar_estado_assinatura: p_user_id obrigatório';
  end if;

  select * into v_existente
  from public.subscriptions
  where user_id = p_user_id
  for update;

  -- Convergência: se o estado NÃO concede acesso e o acesso vigente foi
  -- concedido por OUTRO provider (ainda ativo), ignoramos o rebaixamento.
  if not v_concede
     and v_existente.user_id is not null
     and v_existente.provider is distinct from p_provider
     and v_existente.status in ('active','trialing','grace')
     and v_existente.current_period_end > now()
  then
    return v_existente;
  end if;

  insert into public.subscriptions as s (
    user_id, provider, status, product_id,
    current_period_end, cancel_at_period_end, provider_sub_id, updated_at
  )
  values (
    p_user_id, p_provider, p_status, p_product_id,
    p_current_period_end, coalesce(p_cancel_at_period_end, false),
    p_provider_sub_id, now()
  )
  on conflict (user_id) do update set
    provider             = excluded.provider,
    status               = excluded.status,
    product_id           = excluded.product_id,
    current_period_end   = excluded.current_period_end,
    cancel_at_period_end = excluded.cancel_at_period_end,
    provider_sub_id      = excluded.provider_sub_id,
    updated_at           = now()
  returning * into v_resultado;

  return v_resultado;
end;
$$;

-- Só service role escreve o entitlement. NUNCA conceder a authenticated/anon.
revoke all on function public.aplicar_estado_assinatura(
  uuid, text, text, text, timestamptz, boolean, text
) from public;
grant execute on function public.aplicar_estado_assinatura(
  uuid, text, text, text, timestamptz, boolean, text
) to service_role;
