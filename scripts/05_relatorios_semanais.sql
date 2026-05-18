-- ============================================================================
-- Kairo · 05_relatorios_semanais.sql
-- Cartas semanais do Mentor (geradas pelo Claude Sonnet via Edge Function)
-- ============================================================================

create table if not exists public.relatorios_semanais (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users(id) on delete cascade,
  semana_inicio   date        not null,
  semana_fim      date        not null,
  observacoes     text,
  padroes         text,
  conquistas      text,
  pergunta        text,
  created_at      timestamptz default now(),
  unique (user_id, semana_inicio)
);

create index if not exists relatorios_user_semana_idx
  on public.relatorios_semanais (user_id, semana_inicio desc);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.relatorios_semanais enable row level security;

drop policy if exists "relatorios_select_own" on public.relatorios_semanais;
create policy "relatorios_select_own"
  on public.relatorios_semanais for select
  using (auth.uid() = user_id);

drop policy if exists "relatorios_insert_own" on public.relatorios_semanais;
create policy "relatorios_insert_own"
  on public.relatorios_semanais for insert
  with check (auth.uid() = user_id);

drop policy if exists "relatorios_update_own" on public.relatorios_semanais;
create policy "relatorios_update_own"
  on public.relatorios_semanais for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
