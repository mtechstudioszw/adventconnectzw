-- =====================================================================
--  PATCH 301 — private storage for end-to-end encrypted chat backups
--  STATUS: APPLIED 1 Nov 2026 (by Claude via the Supabase connector)
--
--  The app seals each member's readable chat history with a key derived
--  from a password only they know (ChatBackupService), and uploads the
--  sealed file to chat_backups/<their user id>/backup.bin. This bucket is
--  private and each member can only touch their own folder. The server
--  holds ciphertext; without the member's password nobody can open it.
--
--  CLAUDE.md checklist: no profiles change; no triggers.
-- =====================================================================

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('chat_backups', 'chat_backups', false, 52428800)  -- 50 MB
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS chat_backups_own_select ON storage.objects;
DROP POLICY IF EXISTS chat_backups_own_insert ON storage.objects;
DROP POLICY IF EXISTS chat_backups_own_update ON storage.objects;
DROP POLICY IF EXISTS chat_backups_own_delete ON storage.objects;

CREATE POLICY chat_backups_own_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'chat_backups'
         AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY chat_backups_own_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_backups'
              AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY chat_backups_own_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'chat_backups'
         AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'chat_backups'
              AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY chat_backups_own_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'chat_backups'
         AND (storage.foldername(name))[1] = auth.uid()::text);

COMMIT;
