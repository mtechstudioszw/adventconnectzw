-- =====================================================================
--  PATCH 057 — Fix chat media/voice upload rejection (regression)
--
--  patch_052 added conversations.name (group name). The chat_media /
--  voice_notes storage policies contained:
--      EXISTS (SELECT 1 FROM conversations c
--              WHERE c.id::text = (storage.foldername(name))[1] ...)
--  Inside that subquery the bare `name` now binds to conversations.name
--  (group name, NULL for 1:1) instead of storage.objects.name (the file
--  path) — Postgres even rewrote it to foldername(c.name). Result: the
--  EXISTS never matches for 1:1 chats, so image + voice UPLOADS are
--  rejected by RLS while text (no upload) still works.
--
--  Fix: evaluate foldername(name) at the POLICY top level (only
--  storage.objects in scope → unambiguous) and push the participant
--  lookup into a SECURITY DEFINER helper, mirroring is_conversation_
--  member_text.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.is_conversation_participant_text(p_conv TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id::text = p_conv
      AND (c.participant_a_id = auth.uid() OR c.participant_b_id = auth.uid())
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant_text(TEXT)
  TO authenticated;

-- ----- chat_media --------------------------------------------------
DROP POLICY IF EXISTS "chat_media_select_participants" ON storage.objects;
CREATE POLICY "chat_media_select_participants" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'chat_media'
    AND (
      public.is_conversation_participant_text((storage.foldername(name))[1])
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );

DROP POLICY IF EXISTS "chat_media_insert_participant_self" ON storage.objects;
CREATE POLICY "chat_media_insert_participant_self" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (
      public.is_conversation_participant_text((storage.foldername(name))[1])
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );

-- ----- voice_notes -------------------------------------------------
DROP POLICY IF EXISTS "voice_notes_select_participants" ON storage.objects;
CREATE POLICY "voice_notes_select_participants" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'voice_notes'
    AND (
      public.is_conversation_participant_text((storage.foldername(name))[1])
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );

DROP POLICY IF EXISTS "voice_notes_insert_participant_self" ON storage.objects;
CREATE POLICY "voice_notes_insert_participant_self" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'voice_notes'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (
      public.is_conversation_participant_text((storage.foldername(name))[1])
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );
