-- =====================================================================
--  PATCH 051 — Private chat_media storage bucket (images + documents)
--
--  WHY:  Chat now supports image and document messages (NO video). DMs
--        are private, so — like voice_notes (patch_004) — these live in a
--        private bucket with participant-only, path-based RLS. Public
--        product/profile buckets are wrong here.
--
--  Path layout written by the app:
--        chat_media/{conversation_id}/{sender_user_id}/{timestamp}.{ext}
--
--  RLS mirrors voice_notes: read = participant of the conversation in the
--  path; write = participant AND second segment is the caller's uid;
--  delete = original uploader. When group chats land, extend SELECT/
--  INSERT to also allow group members.
--
--  IDEMPOTENT: yes.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat_media', 'chat_media', FALSE)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "chat_media_select_participants" ON storage.objects;
DROP POLICY IF EXISTS "chat_media_insert_participant_self" ON storage.objects;
DROP POLICY IF EXISTS "chat_media_delete_self" ON storage.objects;

CREATE POLICY "chat_media_select_participants" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'chat_media'
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

CREATE POLICY "chat_media_insert_participant_self" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'chat_media'
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

CREATE POLICY "chat_media_delete_self" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
