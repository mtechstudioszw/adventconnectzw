-- =====================================================================
--  PATCH 004 — Voice-notes storage bucket
--
--  WHY:  Adds a private `voice_notes` bucket so chats can attach short
--        audio clips. Public buckets in patch_002 are fine for product /
--        profile photos, but DMs are private — anyone with a URL
--        shouldn't be able to listen in.
--
--  Path layout written by the app:
--        voice_notes/{conversation_id}/{sender_user_id}/{timestamp}.m4a
--
--  RLS therefore needs to know:
--   - which conversation the file belongs to (foldername index 1)
--   - whether the calling user is a participant in that conversation
--     (read via the scalar participant_a_id / participant_b_id columns
--      added in patch_003).
--
--  PREREQUISITES: schema.sql + patch_001 + patch_002 + patch_003 run.
--  IDEMPOTENT:    yes — `IF NOT EXISTS`, re-creatable policies.
-- =====================================================================


-- ----- Bucket --------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('voice_notes', 'voice_notes', FALSE)
ON CONFLICT (id) DO NOTHING;


-- ----- Storage RLS for voice_notes ----------------------------------
-- Read: participant of the conversation referenced in the path.
-- Write: same, plus the second path segment must equal the user's uid
-- (a sender can only drop files into their own folder).
-- Delete: only the original uploader.

DROP POLICY IF EXISTS "voice_notes_select_participants" ON storage.objects;
DROP POLICY IF EXISTS "voice_notes_insert_participant_self" ON storage.objects;
DROP POLICY IF EXISTS "voice_notes_delete_self" ON storage.objects;

CREATE POLICY "voice_notes_select_participants" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'voice_notes'
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id::text = (storage.foldername(name))[1]
        AND (
          c.participant_a_id = auth.uid()
          OR c.participant_b_id = auth.uid()
        )
    )
  );

CREATE POLICY "voice_notes_insert_participant_self" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'voice_notes'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id::text = (storage.foldername(name))[1]
        AND (
          c.participant_a_id = auth.uid()
          OR c.participant_b_id = auth.uid()
        )
    )
  );

CREATE POLICY "voice_notes_delete_self" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'voice_notes'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
