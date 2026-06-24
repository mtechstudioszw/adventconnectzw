-- =====================================================================
--  PATCH 127 — authoritative per-user inbox previews
--
--  Bug (#3): conversations.last_message is a SHARED column, but
--  "delete for me" is per-user. When you delete-for-me the LAST message,
--  the inbox kept showing it (the shared column can't express a per-user
--  hide). The client had a fragile text/timestamp heuristic to paper over
--  this; this RPC replaces it with the real answer.
--
--  Returns the latest NON-hidden message per conversation for the caller —
--  exactly what WhatsApp shows (the previous message surfaces once you hide
--  the last one). Covers 1:1 chats (participant) and groups the caller is
--  still a member of. Church groups (implicit membership) aren't included,
--  so the client just keeps the shared column for those (safe fallback).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.my_inbox_previews()
RETURNS TABLE (
  conversation_id BIGINT,
  content         TEXT,
  message_type    TEXT,
  created_at      TIMESTAMPTZ,
  sender_id       UUID
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT DISTINCT ON (m.conversation_id)
         m.conversation_id, m.content, m.message_type, m.created_at, m.sender_id
    FROM public.messages m
   WHERE m.conversation_id IN (
           SELECT c.id FROM public.conversations c
            WHERE c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid()
           UNION
           SELECT cm.conversation_id FROM public.conversation_members cm
            WHERE cm.user_id = auth.uid() AND cm.left_at IS NULL
         )
     AND NOT EXISTS (
           SELECT 1 FROM public.hidden_messages h
            WHERE h.message_id = m.id AND h.user_id = auth.uid()
         )
   ORDER BY m.conversation_id, m.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.my_inbox_previews() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_inbox_previews() TO authenticated;
