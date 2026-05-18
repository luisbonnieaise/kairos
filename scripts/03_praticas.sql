-- ============================================================================
-- Kairo · 03_praticas.sql
-- Práticas (hábitos do Pátio/Dôjo) + registro de conclusão diária
-- ============================================================================

-- ── Tabela: praticas ────────────────────────────────────────────────────────
create table if not exists public.praticas (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  nome        text        not null,
  duracao     text,
  categoria   text,
  ativa       boolean     default true,
  created_at  timestamptz default now()
);

create index if not exists praticas_user_ativa_idx
  on public.praticas (user_id, ativa);

alter table public.praticas enable row level security;

drop policy if exists "praticas_select_own" on public.praticas;
create policy "praticas_select_own"
  on public.praticas for select
  using (auth.uid() = user_id);

drop policy if exists "praticas_insert_own" on public.praticas;
create policy "praticas_insert_own"
  on public.praticas for insert
  with check (auth.uid() = user_id);

drop policy if exists "praticas_update_own" on public.praticas;
create policy "praticas_update_own"
  on public.praticas for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "praticas_delete_own" on public.praticas;
create policy "praticas_delete_own"
  on public.praticas for delete
  using (auth.uid() = user_id);

-- ── Tabela: pratica_completadas ─────────────────────────────────────────────
create table if not exists public.pratica_completadas (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  pratica_id  uuid        not null references public.praticas(id) on delete cascade,
  data        date        not null,
  created_at  timestamptz default now(),
  unique (user_id, pratica_id, data)
);

create index if not exists pratica_completadas_user_data_idx
  on public.pratica_completadas (user_id, data);

create index if not exists pratica_completadas_pratica_data_idx
  on public.pratica_completadas (pratica_id, data);

alter table public.pratica_completadas enable row level security;

drop policy if exists "pratica_completadas_select_own" on public.pratica_completadas;
create policy "pratica_completadas_select_own"
  on public.pratica_completadas for select
  using (auth.uid() = user_id);

drop policy if exists "pratica_completadas_insert_own" on public.pratica_completadas;
create policy "pratica_completadas_insert_own"
  on public.pratica_completadas for insert
  with check (auth.uid() = user_id);

drop policy if exists "pratica_completadas_delete_own" on public.pratica_completadas;
create policy "pratica_completadas_delete_own"
  on public.pratica_completadas for delete
  using (auth.uid() = user_id);
