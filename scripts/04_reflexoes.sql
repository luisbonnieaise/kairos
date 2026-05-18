-- ============================================================================
-- Kairo · 04_reflexoes.sql
-- Reflexões escritas pelo usuário (Jardim) — manhã / tarde / noite
-- ============================================================================

create table if not exists public.reflexoes (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  momento     text        not null,
  pergunta    text        not null,
  resposta    text        not null,
  created_at  timestamptz default now()
);

create index if not exists reflexoes_user_created_idx
  on public.reflexoes (user_id, created_at desc);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.reflexoes enable row level security;

drop policy if exists "reflexoes_select_own" on public.reflexoes;
create policy "reflexoes_select_own"
  on public.reflexoes for select
  using (auth.uid() = user_id);

drop policy if exists "reflexoes_insert_own" on public.reflexoes;
create policy "reflexoes_insert_own"
  on public.reflexoes for insert
  with check (auth.uid() = user_id);

drop policy if exists "reflexoes_delete_own" on public.reflexoes;
create policy "reflexoes_delete_own"
  on public.reflexoes for delete
  using (auth.uid() = user_id);
