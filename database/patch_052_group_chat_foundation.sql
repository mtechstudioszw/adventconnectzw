-- =====================================================================
--  PATCH 052 — Group chat foundation
--
--  Strategy: GROUPS REUSE the conversations + messages tables so the
--  whole existing chat stack (chat screen, receipts, realtime, media)
--  works unchanged. A group is a conversations row with is_group=TRUE
--  and its members in a new conversation_members table; the 1:1
--  participant_a_id/participant_b_id columns are simply left NULL for
--  groups.
--
--  1:1 chats are UNAFFECTED — every policy below keeps the original
--  participant check and only adds an OR for group membership, gated by
--  SECURITY DEFINER helpers so membership lookups can't recurse through
--  RLS.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ----- 1. Group columns on conversations (nullable; 1:1 unaffected) ---
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS is_group    BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS name        TEXT,
  ADD COLUMN IF NOT EXISTS photo_url   TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS created_by  UUID REFERENCES public.profiles(id);

-- Groups don't use the pairwise participant columns.
ALTER TABLE public.conversations
  ALTER COLUMN participant_a_id DROP NOT NULL,
  ALTER COLUMN participant_b_id DROP NOT NULL;

-- ----- 2. Membership table -------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversation_members (
  conversation_id BIGINT NOT NULL
    REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  role            TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('admin', 'member')),
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS conversation_members_user_idx
  ON public.conversation_members (user_id);
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;

-- ----- 3. SECURITY DEFINER membership helpers (no RLS recursion) ------
CREATE OR REPLACE FUNCTION public.is_conversation_member(p_conversation BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members m
    WHERE m.conversation_id = p_conversation
      AND m.user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_conversation_admin(p_conversation BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members m
    WHERE m.conversation_id = p_conversation
      AND m.user_id = auth.uid()
      AND m.role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;

-- Text variant for storage policies (foldername is text; avoids a
-- uuid cast that could throw on a malformed path).
CREATE OR REPLACE FUNCTION public.is_conversation_member_text(p_conv TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members m
    WHERE m.conversation_id::text = p_conv
      AND m.user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_conversation_member(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_admin(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_member_text(TEXT) TO authenticated;

-- ----- 4. conversation_members RLS -----------------------------------
-- Read: your own rows + co-members of conversations you're in.
-- Writes happen through SECURITY DEFINER RPCs (patch_053), EXCEPT a
-- member may always remove THEMSELVES (leave group).
DROP POLICY IF EXISTS conversation_members_select ON public.conversation_members;
CREATE POLICY conversation_members_select ON public.conversation_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.is_conversation_member(conversation_id)
  );

DROP POLICY IF EXISTS conversation_members_delete_self ON public.conversation_members;
CREATE POLICY conversation_members_delete_self ON public.conversation_members
  FOR DELETE USING (user_id = auth.uid());

-- ----- 5. Extend conversations policies for members ------------------
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    auth.uid() = participant_a_id
    OR auth.uid() = participant_b_id
    OR public.is_conversation_member(id)
  );

DROP POLICY IF EXISTS "conversations_update_participant" ON public.conversations;
CREATE POLICY "conversations_update_participant" ON public.conversations
  FOR UPDATE USING (
    (auth.uid() = participant_a_id
     OR auth.uid() = participant_b_id
     OR public.is_conversation_member(id))
    AND public.user_is_active()
  ) WITH CHECK (
    (auth.uid() = participant_a_id
     OR auth.uid() = participant_b_id
     OR public.is_conversation_member(id))
    AND public.user_is_active()
  );

-- ----- 6. Extend messages policies for members -----------------------
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND (auth.uid() = c.participant_a_id
             OR auth.uid() = c.participant_b_id)
    )
    OR public.is_conversation_member(messages.conversation_id)
  );

DROP POLICY IF EXISTS "messages_insert_sender" ON public.messages;
CREATE POLICY "messages_insert_sender" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND public.user_is_active()
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = messages.conversation_id
          AND (auth.uid() = c.participant_a_id
               OR auth.uid() = c.participant_b_id)
      )
      OR public.is_conversation_member(messages.conversation_id)
    )
  );

-- ----- 7. Extend storage policies for group members ------------------
DROP POLICY IF EXISTS "chat_media_select_participants" ON storage.objects;
CREATE POLICY "chat_media_select_participants" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'chat_media'
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id::text = (storage.foldername(name))[1]
          AND (c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid())
      )
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );

DROP POLICY IF EXISTS "chat_media_insert_participant_self" ON storage.objects;
CREATE POLICY "chat_media_insert_participant_self" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id::text = (storage.foldername(name))[1]
          AND (c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid())
      )
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );

DROP POLICY IF EXISTS "voice_notes_select_participants" ON storage.objects;
CREATE POLICY "voice_notes_select_participants" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'voice_notes'
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id::text = (storage.foldername(name))[1]
          AND (c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid())
      )
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );

DROP POLICY IF EXISTS "voice_notes_insert_participant_self" ON storage.objects;
CREATE POLICY "voice_notes_insert_participant_self" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'voice_notes'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (
      EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id::text = (storage.foldername(name))[1]
          AND (c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid())
      )
      OR public.is_conversation_member_text((storage.foldername(name))[1])
    )
  );
