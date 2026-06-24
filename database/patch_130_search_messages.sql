-- =====================================================================
--  PATCH 130 — full-text message search for Advent Chat
--
--  The chat search's "Messages" scope only matched the conversation's
--  denormalised last_message preview. This RPC searches the ACTUAL message
--  history (text/content) across every conversation the caller belongs to,
--  so a result can deep-link to that exact message.
--
--  Scoped to the caller's own conversations (1:1 + groups they're a member
--  of), excludes messages they deleted-for-me and soft-deleted tombstones.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.search_my_messages(p_query TEXT, p_limit INT DEFAULT 50)
RETURNS TABLE (
  message_id      BIGINT,
  conversation_id BIGINT,
  content         TEXT,
  created_at      TIMESTAMPTZ,
  sender_id       UUID
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT m.id, m.conversation_id, m.content, m.created_at, m.sender_id
    FROM public.messages m
   WHERE m.conversation_id IN (
           SELECT c.id FROM public.conversations c
            WHERE c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid()
           UNION
           SELECT cm.conversation_id FROM public.conversation_members cm
            WHERE cm.user_id = auth.uid() AND cm.left_at IS NULL
         )
     AND coalesce(m.is_deleted, false) = false
     AND m.message_type = 'text'
     AND m.content ILIKE '%' || btrim(p_query) || '%'
     AND NOT EXISTS (
           SELECT 1 FROM public.hidden_messages h
            WHERE h.message_id = m.id AND h.user_id = auth.uid()
         )
   ORDER BY m.created_at DESC
   LIMIT greatest(1, least(p_limit, 100));
$$;

REVOKE ALL ON FUNCTION public.search_my_messages(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_my_messages(TEXT, INT) TO authenticated;
