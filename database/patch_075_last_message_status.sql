-- =====================================================================
--  PATCH 075 — last outgoing message status (inbox ticks)
--
--  The chat list shows no delivery state on the last message. This RPC
--  returns, for each conversation whose MOST RECENT message was sent by
--  the caller, whether it's delivered / read — so the inbox tile can
--  show ✓ / ✓✓ / ✓✓(blue), exactly like inside the chat. Conversations
--  whose last message is from the OTHER person are simply not returned
--  (the tile shows no tick for them).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.last_outgoing_message_status()
RETURNS TABLE (conversation_id BIGINT, delivered BOOLEAN, is_read BOOLEAN) AS $$
  SELECT last_msg.conversation_id,
         (last_msg.delivered_at IS NOT NULL) AS delivered,
         last_msg.read AS is_read
    FROM (
      SELECT DISTINCT ON (m.conversation_id)
             m.conversation_id, m.sender_id, m.delivered_at, m.read
        FROM public.messages m
       WHERE m.message_type <> 'system'
       ORDER BY m.conversation_id, m.created_at DESC
    ) AS last_msg
   WHERE last_msg.sender_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.last_outgoing_message_status() TO authenticated;
