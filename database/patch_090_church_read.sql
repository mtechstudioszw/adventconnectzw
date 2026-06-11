-- =====================================================================
--  PATCH 090 — unread tracking for church groups (implicit membership)
--
--  Church groups have no conversation_members rows, so the per-member
--  last-read marker (patch_060) didn't apply and their messages showed as
--  already read. We store a per-user last_read_at on conversation_state
--  and count church messages newer than it (and newer than the join
--  floor) that someone else sent.
-- =====================================================================

ALTER TABLE public.conversation_state
  ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;

-- Stamp "read up to now" for the caller in a conversation.
CREATE OR REPLACE FUNCTION public.mark_conversation_read_at(p_conv BIGINT)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.conversation_state (user_id, conversation_id, last_read_at)
  VALUES (auth.uid(), p_conv, now())
  ON CONFLICT (user_id, conversation_id)
  DO UPDATE SET last_read_at = now();
$$;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read_at(BIGINT) TO authenticated;

-- Unread count per church group for the caller.
CREATE OR REPLACE FUNCTION public.church_unread_counts()
RETURNS TABLE (conversation_id BIGINT, unread INTEGER)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c.id,
         (SELECT count(*)::int FROM public.messages m
           WHERE m.conversation_id = c.id
             AND m.message_type <> 'system'
             AND m.sender_id <> auth.uid()
             AND m.created_at > GREATEST(
                   cs.last_read_at,
                   pr.church_changed_at,
                   'epoch'::timestamptz))
    FROM public.conversations c
    JOIN public.profiles pr ON pr.id = auth.uid()
    LEFT JOIN public.conversation_state cs
           ON cs.user_id = auth.uid() AND cs.conversation_id = c.id
   WHERE c.church_id IS NOT NULL AND c.church_id = pr.church_id;
$$;
GRANT EXECUTE ON FUNCTION public.church_unread_counts() TO authenticated;
