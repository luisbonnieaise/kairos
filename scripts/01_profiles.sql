-- ============================================================================
-- Kairo · 01_profiles.sql
-- Perfil do usuário (1-para-1 com auth.users)
-- ============================================================================

create table if not exists public.profiles (
  id                uuid        primary key references auth.users(id) on delete cascade,
  nome              text,
  identidade        text,
  desequilibrio     text,
  area_foco         text,
  ritmo             text,
  horario_lembrete  time,
  idioma            text        default 'pt',
  notif_jardim      boolean     default true,
  avatar_url        text,
  tutoriais_vistos  jsonb       default '{}'::jsonb,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ── Trigger: cria perfil automaticamente no signup ──────────────────────────
create or replace function public.handle_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_novo_usuario();
