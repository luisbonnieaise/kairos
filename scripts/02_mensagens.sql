-- ============================================================================
-- Kairo · 02_mensagens.sql
-- Histórico de conversas com o Mentor (Claude Haiku/Sonnet)
-- ============================================================================

create table if not exists public.mensagens (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  role        text        not null check (role in ('user', 'assistant')),
  conteudo    text        not null,
  created_at  timestamptz default now()
);

create index if not exists mensagens_user_created_idx
  on public.mensagens (user_id, created_at desc);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.mensagens enable row level security;

drop policy if exists "mensagens_select_own" on public.mensagens;
create policy "mensagens_select_own"
  on public.mensagens for select
  using (auth.uid() = user_id);

drop policy if exists "mensagens_insert_own" on public.mensagens;
create policy "mensagens_insert_own"
  on public.mensagens for insert
  with check (auth.uid() = user_id);

drop policy if exists "mensagens_delete_own" on public.mensagens;
create policy "mensagens_delete_own"
  on public.mensagens for delete
  using (auth.uid() = user_id);
