-- ============================================================================
-- Kairo · 06_storage_avatares.sql
-- Bucket de avatares no Supabase Storage (nome: "profire")
-- Estrutura: profire/<user_id>/avatar.<ext>
-- ============================================================================

-- ── Cria o bucket público (idempotente) ─────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('profire', 'profire', true)
on conflict (id) do update set public = excluded.public;

-- ── Policies ────────────────────────────────────────────────────────────────
-- Leitura pública (o app exibe avatar via URL pública)
drop policy if exists "avatar_public_read" on storage.objects;
create policy "avatar_public_read"
  on storage.objects for select
  using (bucket_id = 'profire');

-- Upload: só dentro da própria pasta (primeiro segmento = user_id)
drop policy if exists "avatar_insert_own" on storage.objects;
create policy "avatar_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'profire'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Update (upsert: true do app)
drop policy if exists "avatar_update_own" on storage.objects;
create policy "avatar_update_own"
  on storage.objects for update
  using (
    bucket_id = 'profire'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'profire'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Remoção
drop policy if exists "avatar_delete_own" on storage.objects;
create policy "avatar_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'profire'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
