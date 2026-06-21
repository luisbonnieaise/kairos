-- ============================================================================
-- Kairo · 13_checkout_first_email.sql
-- Checkout-first na landing page: a assinatura web passa a abrir o Stripe
-- Checkout SEM login (substitui o gate de login por OTP do doc 07 / PROMPT 7.3).
-- A conta é vinculada pelo E-MAIL que a pessoa informa no próprio Checkout.
--
-- Fluxo (ver lp-kairo/src/app/api/checkout/route.ts + stripe-webhook/index.ts):
--   • Conta JÁ existe (e-mail bate em auth.users) → concede o entitlement na
--     hora, via a RPC canônica aplicar_estado_assinatura.
--   • Conta NÃO existe ainda (pagou antes de criar conta no app) → guarda em
--     pending_entitlements; o trigger de signup reconcilia ao criar a conta.
--
-- ADITIVO: não altera subscriptions nem aplicar_estado_assinatura; só
-- acrescenta a ponte por e-mail. Pode rodar em produção. Depende do
-- 12_billing_multiplataforma.sql (RPC canônica + vocabulário de status).
-- ============================================================================

-- ── 1. pending_entitlements: entitlement à espera de uma conta ──────────────
-- 1 linha por e-mail (lowercased). Mesmo vocabulário de status/provider de
-- subscriptions. Escrita só por service role / funções SECURITY DEFINER.
create table if not exists public.pending_entitlements (
  email                text        primary key,
  provider             text        not null default 'stripe',
  status               text        not null,
  product_id           text,
  current_period_end   timestamptz,
  cancel_at_period_end boolean     not null default false,
  provider_sub_id      text,
  stripe_customer_id   text,
  updated_at           timestamptz not null default now(),
  constraint pending_entitlements_provider_check
    check (provider in ('stripe','apple','google')),
  constraint pending_entitlements_status_check
    check (status in (
      'none','incomplete','incomplete_expired','trialing','active',
      'past_due','canceled','unpaid','paused','grace','expired'))
);

alter table public.pending_entitlements enable row level security;
-- Intencionalmente SEM policy: RLS on sem policy = invisível a anon/auth. Só
-- service role (bypassa RLS) e funções SECURITY DEFINER (owner) acessam.

-- ── 2. aplicar_estado_por_email(): concede por e-mail OU guarda pendente ────
-- Chamada pelo stripe-webhook quando NÃO há user_id ancorado (checkout-first).
-- Se existe conta com o e-mail → delega à RPC canônica (concede e fixa o
-- stripe_customer_id p/ resolução futura). Senão → UPSERT em
-- pending_entitlements (idempotente por e-mail). Devolve 'granted' | 'pending'.
create or replace function public.aplicar_estado_por_email(
  p_email                text,
  p_provider             text,
  p_status               text,
  p_product_id           text,
  p_current_period_end   timestamptz,
  p_cancel_at_period_end boolean default false,
  p_provider_sub_id      text default null,
  p_stripe_customer_id   text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text := lower(trim(p_email));
  v_user_id uuid;
begin
  if v_email is null or v_email = '' then
    raise exception 'aplicar_estado_por_email: e-mail obrigatório';
  end if;

  -- auth.users é a fonte de identidade. Conta mais antiga vence (determinístico).
  select id into v_user_id
  from auth.users
  where lower(email) = v_email
  order by created_at asc
  limit 1;

  if v_user_id is not null then
    perform public.aplicar_estado_assinatura(
      v_user_id, p_provider, p_status, p_product_id,
      p_current_period_end, p_cancel_at_period_end, p_provider_sub_id
    );
    if p_stripe_customer_id is not null then
      update public.subscriptions
        set stripe_customer_id = p_stripe_customer_id, updated_at = now()
        where user_id = v_user_id;
    end if;
    -- já aplicado: limpa qualquer pendência residual desse e-mail.
    delete from public.pending_entitlements where email = v_email;
    return 'granted';
  end if;

  -- Sem conta ainda: guarda pendente (reconciliado no signup).
  insert into public.pending_entitlements as pe (
    email, provider, status, product_id, current_period_end,
    cancel_at_period_end, provider_sub_id, stripe_customer_id, updated_at
  ) values (
    v_email, p_provider, p_status, p_product_id, p_current_period_end,
    coalesce(p_cancel_at_period_end, false), p_provider_sub_id,
    p_stripe_customer_id, now()
  )
  on conflict (email) do update set
    provider             = excluded.provider,
    status               = excluded.status,
    product_id           = excluded.product_id,
    current_period_end   = excluded.current_period_end,
    cancel_at_period_end = excluded.cancel_at_period_end,
    provider_sub_id      = excluded.provider_sub_id,
    stripe_customer_id   = excluded.stripe_customer_id,
    updated_at           = now();
  return 'pending';
end;
$$;

revoke all on function public.aplicar_estado_por_email(
  text, text, text, text, timestamptz, boolean, text, text
) from public;
grant execute on function public.aplicar_estado_por_email(
  text, text, text, text, timestamptz, boolean, text, text
) to service_role;

-- ── 3. Reconciliação no signup ──────────────────────────────────────────────
-- Ao criar a conta (auth.users insert), se houver pending_entitlements com o
-- mesmo e-mail, aplica via RPC canônica e remove o pendente. SECURITY DEFINER
-- (lê pending, lê auth, escreve subscriptions). NUNCA bloqueia o signup: erros
-- viram warning (o restore por e-mail no app cobre o caso raro de falha).
create or replace function public.reconciliar_pending_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(NEW.email));
  v_pe    public.pending_entitlements;
begin
  if v_email is null or v_email = '' then
    return NEW;
  end if;

  select * into v_pe from public.pending_entitlements where email = v_email;
  if v_pe.email is null then
    return NEW;
  end if;

  begin
    perform public.aplicar_estado_assinatura(
      NEW.id, v_pe.provider, v_pe.status, v_pe.product_id,
      v_pe.current_period_end, v_pe.cancel_at_period_end, v_pe.provider_sub_id
    );
    if v_pe.stripe_customer_id is not null then
      update public.subscriptions
        set stripe_customer_id = v_pe.stripe_customer_id, updated_at = now()
        where user_id = NEW.id;
    end if;
    delete from public.pending_entitlements where email = v_email;
  exception when others then
    raise warning 'reconciliar_pending_entitlement falhou p/ %: %', v_email, sqlerrm;
  end;

  return NEW;
end;
$$;

drop trigger if exists on_auth_user_created_reconcile on auth.users;
create trigger on_auth_user_created_reconcile
  after insert on auth.users
  for each row execute function public.reconciliar_pending_entitlement();
