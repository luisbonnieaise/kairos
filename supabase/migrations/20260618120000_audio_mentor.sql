-- Feature de áudio para o Mentor (mensagem de voz + transcrição no servidor).
--
-- Acrescenta, na tabela existente `public.mensagens`, o caminho do áudio no
-- Storage e a duração da gravação. Ambas as colunas são NULLABLE: mensagens de
-- texto continuam tendo `audio_path` e `audio_duracao_ms` nulos. Nenhuma
-- mudança de RLS na tabela — as policies de `mensagens` por `user_id` já
-- cobrem as novas colunas.
--
-- Idempotente (ADD COLUMN IF NOT EXISTS / on conflict / drop policy if exists)
-- para poder reaplicar com segurança. O schema base foi criado pelo painel do
-- Supabase, então esta é a primeira migration que toca esses objetos.

-- ── 1. Colunas de áudio em mensagens ────────────────────────────────────────
alter table public.mensagens
  add column if not exists audio_path text;

alter table public.mensagens
  add column if not exists audio_duracao_ms integer;

comment on column public.mensagens.audio_path is
  'Caminho do arquivo de voz no bucket privado audios-mentor ({uid}/{ts}.m4a). Nulo em mensagens de texto.';
comment on column public.mensagens.audio_duracao_ms is
  'Duração da gravação em milissegundos. Nulo em mensagens de texto.';

-- ── 2. Bucket privado audios-mentor ─────────────────────────────────────────
-- Privado: o áudio do usuário só é acessível via JWT dele (RLS abaixo) ou pela
-- service role da Edge Function transcrever-audio. Limite de 10 MB por arquivo,
-- alinhado ao teto que a função aplica. MIME restritos a formatos de voz.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'audios-mentor',
  'audios-mentor',
  false,
  10485760, -- 10 MB
  array['audio/mp4', 'audio/m4a', 'audio/aac', 'audio/mpeg', 'audio/x-m4a', 'audio/webm']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── 3. RLS no Storage: cada usuário só enxerga a própria pasta {uid}/ ────────
-- Padrão canônico do Supabase: a 1ª parte do caminho (storage.foldername(name)[1])
-- precisa bater com o auth.uid(). A service role (Edge Function) ignora RLS e
-- consegue baixar qualquer áudio para transcrever.

drop policy if exists "audios-mentor: dono lê" on storage.objects;
create policy "audios-mentor: dono lê"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'audios-mentor'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "audios-mentor: dono envia" on storage.objects;
create policy "audios-mentor: dono envia"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'audios-mentor'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "audios-mentor: dono apaga" on storage.objects;
create policy "audios-mentor: dono apaga"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'audios-mentor'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
