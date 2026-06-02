-- ============================================================================
-- Kairo · 07_uso_ia.sql
-- Ledger server-side de uso de IA (auditoria + rate-limit não-burlável).
-- Escrito SOMENTE pelas Edge Functions via service role — nunca pelo client.
-- Inclui a função canônica de gating de assinatura public.is_premium().
-- ============================================================================

-- ── Tabela de uso de IA ─────────────────────────────────────────────────────
-- Cada linha = uma chamada efetiva à Anthropic feita por uma Edge Function.
-- A contagem por janela (rate limit) lê esta tabela; como só a função grava
-- (service role, que bypassa RLS), o cliente não tem como inflar/zerar o uso.
create table if not exists public.uso_ia (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  funcao      text        not null check (funcao in ('mentor-chat','relatorio-semanal')),
  modelo      text        not null,
  created_at  timestamptz not null default now()
);

-- Índice para a contagem por (usuário, função) na última janela de tempo.
create index if not exists uso_ia_user_funcao_created_idx
  on public.uso_ia (user_id, funcao, created_at desc);

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- RLS habilitado. Apenas SELECT da própria linha (para futura tela de
-- histórico). NENHUMA policy de insert/update/delete: a escrita é feita
-- exclusivamente pelas Edge Functions via service role (bypassa RLS).
-- Sem policy de insert, o client não consegue forjar registros de uso.
alter table public.uso_ia enable row level security;

drop policy if exists "uso_ia_select_own" on public.uso_ia;
create policy "uso_ia_select_own"
  on public.uso_ia for select
  using (auth.uid() = user_id);

-- ── Função canônica de gating de assinatura ─────────────────────────────────
-- public.is_premium(uid) → true se o usuário tem acesso premium AGORA.
--
-- Projetada para funcionar ANTES e DEPOIS da Fase 03:
-- a tabela public.subscriptions só nasce na Fase 03 (08_subscriptions.sql).
-- Enquanto ela não existir, o SELECT lança undefined_table; capturamos a
-- exceção e retornamos false — assim a função é segura para ser chamada já
-- agora (todos não-premium até a Fase 03 popular billing).
--
-- security definer + search_path = public: a função precisa enxergar
-- public.subscriptions independente do search_path do chamador, e roda com
-- privilégios do owner (necessário porque subscriptions não terá policy de
-- SELECT que cubra consultar a assinatura de terceiros — aqui só lemos a
-- linha do próprio uid passado pela Edge Function).
create or replace function public.is_premium(uid uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return exists (
    select 1
    from public.subscriptions s
    where s.user_id = uid
      and s.status in ('active','trialing')
      and s.current_period_end > now()
  );
exception
  when undefined_table then
    -- public.subscriptions ainda não criada (pré-Fase 03): ninguém é premium.
    return false;
end;
$$;

grant execute on function public.is_premium(uuid) to authenticated, service_role;
