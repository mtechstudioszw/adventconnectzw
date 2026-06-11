-- =====================================================================
--  PATCH 083 — actually enforce blocking on 1:1 messages
--
--  Bug: blocking (from mini-profile or chat menu) inserted a blocked_users
--  row but the messages INSERT policy never checked it, so a blocked user
--  could still send and the other side still received + got notified.
--  Now a 1:1 insert is rejected when EITHER participant has blocked the
--  other (the sender's optimistic bubble stays at a single tick — silent
--  block, WhatsApp-style; the recipient gets nothing and no notification
--  since the row is never created).
-- =====================================================================

-- True when the two participants of a 1:1 conversation have a block
-- between them (either direction).
CREATE OR REPLACE FUNCTION public.is_conversation_blocked(p_conv BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.conversations c
      JOIN public.blocked_users b
        ON (b.blocker_id = c.participant_a_id AND b.blocked_id = c.participant_b_id)
        OR (b.blocker_id = c.participant_b_id AND b.blocked_id = c.participant_a_id)
     WHERE c.id = p_conv
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_conversation_blocked(BIGINT) TO authenticated;

-- Recreate the send policy (patch_079 version) + the block check on the
-- 1:1 branch. Groups are unaffected (blocking is a 1:1 concept).
DROP POLICY IF EXISTS messages_insert_sender ON public.messages;
CREATE POLICY messages_insert_sender ON public.messages
  FOR INSERT
  WITH CHECK (
    (auth.uid() = sender_id) AND user_is_active() AND (
      (EXISTS (
        SELECT 1 FROM conversations c
         WHERE c.id = messages.conversation_id
           AND (auth.uid() = c.participant_a_id OR auth.uid() = c.participant_b_id)
      ) AND NOT public.is_conversation_blocked(conversation_id))
      OR public.is_active_conversation_member(conversation_id)
    )
  );
