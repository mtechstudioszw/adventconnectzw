-- =====================================================================
--  PATCH 056 — Message actions foundation
--    reply / quote, edit, forward, reactions, starred messages.
--  Reuses the existing conversation access model. Depends on patch_052.
-- =====================================================================

-- ----- 1. New columns on messages ------------------------------------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS reply_to_id BIGINT
    REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS forwarded   BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS edited_at   TIMESTAMPTZ;

-- ----- 2. Access helper (member or 1:1 participant of the msg's convo)
CREATE OR REPLACE FUNCTION public.can_access_message(p_message BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.messages m
      JOIN public.conversations c ON c.id = m.conversation_id
     WHERE m.id = p_message
       AND (
         c.participant_a_id = auth.uid()
         OR c.participant_b_id = auth.uid()
         OR public.is_conversation_member(c.id)
       )
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.can_access_message(BIGINT) TO authenticated;

-- ----- 3. Reactions (one emoji per user per message) -----------------
CREATE TABLE IF NOT EXISTS public.message_reactions (
  message_id BIGINT NOT NULL
    REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji      TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS message_reactions_message_idx
  ON public.message_reactions (message_id);
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
CREATE POLICY message_reactions_select ON public.message_reactions
  FOR SELECT TO authenticated
  USING (public.can_access_message(message_id));

DROP POLICY IF EXISTS message_reactions_insert ON public.message_reactions;
CREATE POLICY message_reactions_insert ON public.message_reactions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.can_access_message(message_id));

DROP POLICY IF EXISTS message_reactions_update ON public.message_reactions;
CREATE POLICY message_reactions_update ON public.message_reactions
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS message_reactions_delete ON public.message_reactions;
CREATE POLICY message_reactions_delete ON public.message_reactions
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ----- 4. Starred messages (private per user) ------------------------
CREATE TABLE IF NOT EXISTS public.starred_messages (
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  message_id BIGINT NOT NULL
    REFERENCES public.messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);
CREATE INDEX IF NOT EXISTS starred_messages_user_idx
  ON public.starred_messages (user_id, created_at DESC);
ALTER TABLE public.starred_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS starred_messages_all ON public.starred_messages;
CREATE POLICY starred_messages_all ON public.starred_messages
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND public.can_access_message(message_id));
