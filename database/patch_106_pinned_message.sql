-- =====================================================================
--  PATCH 106 — pinned message per conversation (WhatsApp-style)
--
--  A single pinned message id on the conversation. set_pinned_message
--  pins/unpins (null = unpin), gated to people in the conversation.
-- =====================================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS pinned_message_id BIGINT;

CREATE OR REPLACE FUNCTION public.set_pinned_message(
  p_conv BIGINT, p_message_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (
        EXISTS (SELECT 1 FROM public.conversations c
                 WHERE c.id = p_conv
                   AND (c.participant_a_id = auth.uid()
                        OR c.participant_b_id = auth.uid()))
        OR public.is_active_conversation_member(p_conv)
        OR public.is_my_church_conv(p_conv)) THEN
    RAISE EXCEPTION 'Not allowed to pin in this conversation.';
  END IF;
  UPDATE public.conversations
     SET pinned_message_id = p_message_id
   WHERE id = p_conv;
END;
$$;
REVOKE ALL ON FUNCTION public.set_pinned_message(BIGINT, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pinned_message(BIGINT, BIGINT) TO authenticated;
