-- ============================================================================
-- Kairo · 09_cron_relatorios.sql
-- Geração agendada de cartas semanais — substitui o burst de domingo on-demand
-- por enfileiramento + dispatcher espalhado.
--
-- Estratégia (documentada):
--   Domingo 00:00 UTC, enfileirar_relatorios_semanais() insere 1 linha por
--   usuário ATIVO na fila cron_relatorios_fila com status='pendente'.
--   A cada minuto, dispatch_relatorios_pendentes(50) consome 50 pendentes via
--   net.http_post para a Edge Function relatorio-semanal (modo CRON com
--   x-cron-secret). 50 req/min ≈ 3.000/h → 30.000 usuários em ~10h.
--   Bem abaixo do rate limit típico da Anthropic e da concorrência da função.
--
-- Idempotência:
--   - cron_relatorios_fila.unique(user_id, semana_inicio): rodar o
--     enfileiramento 2x não duplica linhas.
--   - status='pendente' só é processado por um dispatch (UPDATE … RETURNING
--     usado como "claim"). Mesmo que o cron sobreponha, cada linha é
--     processada uma única vez.
--   - A Edge Function tem idempotência por (user_id, semana_inicio) em
--     relatorios_semanais — chamada duplicada não regera com Claude.
--
-- Pré-requisitos (preencher via SQL Editor; ver docs/06-runbook-deploy.md §6):
--   ALTER DATABASE postgres SET app.cron_secret = '<CRON_SECRET>';
--   ALTER DATABASE postgres SET app.cron_relatorio_url =
--     'https://<projeto>.supabase.co/functions/v1/relatorio-semanal';
--
-- O secret é o MESMO valor de Deno.env CRON_SECRET configurado nas Edge
-- Function secrets. URL e secret ficam em GUC (current_setting) — não em
-- texto puro nas funções — para facilitar rotação.
-- ============================================================================

-- ── Extensões ───────────────────────────────────────────────────────────────
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

-- ── Fila de envio ───────────────────────────────────────────────────────────
-- 1 linha = 1 disparo pendente p/ Edge Function relatorio-semanal (modo CRON).
-- unique(user_id, semana_inicio) garante que enfileirar 2x não duplica.
create table if not exists public.cron_relatorios_fila (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null references auth.users(id) on delete cascade,
  semana_inicio date        not null,
  status        text        not null default 'pendente'
                check (status in ('pendente','enviado','falhou')),
  tentativas    int         not null default 0,
  criado_em     timestamptz not null default now(),
  enviado_em    timestamptz,
  request_id    bigint,
  erro          text,
  unique (user_id, semana_inicio)
);

-- Índice quente do dispatcher: claim do próximo lote pendente em ordem FIFO.
create index if not exists cron_relatorios_fila_pendente_idx
  on public.cron_relatorios_fila (status, criado_em)
  where status = 'pendente';

-- RLS: a fila é interna ao backend. Sem policies → nenhum client a vê/altera.
-- (Funções abaixo são security definer e bypassam RLS pelo dono.)
alter table public.cron_relatorios_fila enable row level security;

-- ── Função: enfileirar_relatorios_semanais ──────────────────────────────────
-- Insere na fila 1 linha por usuário ATIVO (atividade nos últimos 14 dias),
-- para a semana cujo início é a segunda-feira passada (UTC). Idempotente.
-- Atividade = qualquer reflexão, prática completada ou mensagem nos últimos
-- 14 dias (proxy razoável de MAU semanal; evita custo de IA p/ usuários inertes).
create or replace function public.enfileirar_relatorios_semanais()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_semana_inicio date;
  v_inseridas int;
begin
  -- Segunda-feira da semana que acabou. Em UTC: domingo de hoje - 6 dias.
  -- Se today=domingo, semana_fim=today; semana_inicio = today - 6.
  -- Se today=segunda (cron rodou de madrugada e já virou seg.), o domingo
  -- mais recente é ontem; usamos a mesma fórmula geral abaixo.
  v_semana_inicio := (
    (current_date at time zone 'UTC')::date
    - ((extract(dow from (current_date at time zone 'UTC'))::int + 6) % 7)
  );

  with ativos as (
    select user_id from public.reflexoes
      where created_at >= now() - interval '14 days'
    union
    select user_id from public.pratica_completadas
      where data >= (current_date - interval '14 days')
    union
    select user_id from public.mensagens
      where created_at >= now() - interval '14 days'
  )
  insert into public.cron_relatorios_fila (user_id, semana_inicio)
  select distinct a.user_id, v_semana_inicio
    from ativos a
    join auth.users u on u.id = a.user_id
   where not exists (
     select 1 from public.relatorios_semanais r
      where r.user_id = a.user_id and r.semana_inicio = v_semana_inicio
   )
  on conflict (user_id, semana_inicio) do nothing;

  get diagnostics v_inseridas = row_count;
  return v_inseridas;
end;
$$;

-- ── Função: dispatch_relatorios_pendentes ───────────────────────────────────
-- Consome até `lote_max` linhas pendentes e dispara net.http_post para a
-- Edge Function (modo CRON). Marca como 'enviado' antes do POST (claim) para
-- que duas execuções concorrentes do cron NÃO pisem na mesma linha — pg_net
-- é assíncrono, e processar 2x geraria 2 chamadas redundantes (a idempotência
-- da Edge Function as absorveria, mas paga round-trip e poluí o ledger).
--
-- A URL e o secret vêm de GUC (ALTER DATABASE … SET app.*); se ausentes,
-- retorna 0 sem erro (segurança contra disparo acidental antes do setup).
create or replace function public.dispatch_relatorios_pendentes(lote_max int default 50)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text := current_setting('app.cron_relatorio_url', true);
  v_secret text := current_setting('app.cron_secret', true);
  v_count  int  := 0;
  r        record;
  v_req_id bigint;
begin
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    -- Setup incompleto: ALTER DATABASE … SET app.cron_relatorio_url/secret.
    -- Silencioso por design (cron a cada minuto não deve gerar ruído).
    return 0;
  end if;

  -- Claim: marca como 'enviado' antes do POST (ver comentário acima).
  -- ORDER BY criado_em garante FIFO. SKIP LOCKED evita contenção.
  for r in
    update public.cron_relatorios_fila
       set status      = 'enviado',
           enviado_em  = now(),
           tentativas  = tentativas + 1
     where id in (
       select id from public.cron_relatorios_fila
        where status = 'pendente'
        order by criado_em
        limit lote_max
        for update skip locked
     )
    returning id, user_id, semana_inicio
  loop
    select net.http_post(
      url     := v_url,
      body    := jsonb_build_object(
                   'user_id',       r.user_id,
                   'semana_inicio', to_char(r.semana_inicio, 'YYYY-MM-DD')
                 ),
      headers := jsonb_build_object(
                   'Content-Type',   'application/json',
                   'x-cron-secret',  v_secret
                 ),
      timeout_milliseconds := 60000
    ) into v_req_id;

    update public.cron_relatorios_fila
       set request_id = v_req_id
     where id = r.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Permissões: apenas service_role pode invocar (Edge Functions de admin / SQL
-- Editor com role postgres já consegue). authenticated NÃO recebe execute —
-- são funções de back-office de cron.
revoke all on function public.enfileirar_relatorios_semanais() from public;
revoke all on function public.dispatch_relatorios_pendentes(int) from public;
grant execute on function public.enfileirar_relatorios_semanais() to service_role;
grant execute on function public.dispatch_relatorios_pendentes(int) to service_role;

-- ── Agendamentos pg_cron ────────────────────────────────────────────────────
-- Idempotência: unschedule por nome (no-op se não existe) + schedule.
-- pg_cron rejeita schedule se já existe um job com o mesmo nome, por isso o
-- unschedule prévio. cron.unschedule(text) lança se não existe → cobrimos com
-- DO/EXCEPTION.
--
-- Horário escolhido: 00:00 UTC de domingo para o enfileiramento (cobre o
-- domingo inteiro pro dispatcher distribuir). Dispatcher a cada minuto.
-- Trocar fuso/horário: refazer o cron.schedule abaixo com a cron expr nova.
do $$
begin
  perform cron.unschedule('kairo_enfileirar_relatorios_semanais');
exception when others then null;
end$$;

do $$
begin
  perform cron.unschedule('kairo_dispatch_relatorios_pendentes');
exception when others then null;
end$$;

-- Enfileira no domingo às 00:00 UTC. (cron expr: minuto hora dia mês dow)
select cron.schedule(
  'kairo_enfileirar_relatorios_semanais',
  '0 0 * * 0',
  $$select public.enfileirar_relatorios_semanais();$$
);

-- Dispatcher a cada minuto. Quando a fila está vazia, é um SELECT barato.
select cron.schedule(
  'kairo_dispatch_relatorios_pendentes',
  '* * * * *',
  $$select public.dispatch_relatorios_pendentes(50);$$
);
