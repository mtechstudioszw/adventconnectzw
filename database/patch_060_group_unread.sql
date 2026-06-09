-- =====================================================================
--  PATCH 060 — Group unread counts
--
--  messages.read is a single boolean — fine for 1:1, useless for groups
--  (each member reads independently). Track a per-(user, group) last-read
--  timestamp on conversation_state and count newer messages from others.
--  Without this, group threads always showed 0 unread (looked "already
--  opened").
-- =====================================================================

ALTER TABLE public.conversation_state
  ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;

-- Per-group unread counts for the caller: messages from OTHERS newer
-- than the caller's last_read_at for that group.
CREATE OR REPLACE FUNCTION public.get_group_unread_counts()
RETURNS TABLE (conversation_id BIGINT, unread_count INTEGER) AS $$
  SELECT m.conversation_id, COUNT(*)::int
    FROM public.messages m
    JOIN public.conversations c
      ON c.id = m.conversation_id AND COALESCE(c.is_group, FALSE) = TRUE
    JOIN public.conversation_members cm
      ON cm.conversation_id = m.conversation_id AND cm.user_id = auth.uid()
    LEFT JOIN public.conversation_state cs
      ON cs.conversation_id = m.conversation_id AND cs.user_id = auth.uid()
   WHERE m.sender_id <> auth.uid()
     AND m.created_at > COALESCE(cs.last_read_at, '1970-01-01'::timestamptz)
   GROUP BY m.conversation_id;
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.get_group_unread_counts() TO authenticated;

-- Mark a group read for the caller (upsert last_read_at = now).
CREATE OR REPLACE FUNCTION public.mark_group_read(p_conversation BIGINT)
RETURNS VOID AS $$
  INSERT INTO public.conversation_state (user_id, conversation_id, last_read_at)
  VALUES (auth.uid(), p_conversation, now())
  ON CONFLICT (user_id, conversation_id)
  DO UPDATE SET last_read_at = now();
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.mark_group_read(BIGINT) TO authenticated;
