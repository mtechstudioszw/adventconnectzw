-- =====================================================================
--  PATCH 099 — inbox tick: blue only when read_at is set
--
--  last_outgoing_message_status returned the raw `read` boolean, so the
--  inbox blue tick lit even for recipients with read receipts OFF
--  (read=true, read_at=null). Return read_at-based read so the inbox
--  matches the in-chat tick (grey ✓✓ delivered vs blue ✓✓ read).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.last_outgoing_message_status()
RETURNS TABLE (conversation_id BIGINT, delivered BOOLEAN, is_read BOOLEAN) AS $$
  SELECT last_msg.conversation_id,
         (last_msg.delivered_at IS NOT NULL) AS delivered,
         (last_msg.read_at IS NOT NULL) AS is_read
    FROM (
      SELECT DISTINCT ON (m.conversation_id)
             m.conversation_id, m.sender_id, m.delivered_at, m.read_at
        FROM public.messages m
       WHERE m.message_type <> 'system'
       ORDER BY m.conversation_id, m.created_at DESC
    ) AS last_msg
   WHERE last_msg.sender_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.last_outgoing_message_status() TO authenticated;
