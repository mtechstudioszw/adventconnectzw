-- =====================================================================
--  PATCH 038 — mark_conversation_delivered RPC for push handlers
--
--  WHY: The existing mark_message_delivered(UUID[]) requires the
--       caller to know the exact message ids — fine for the chat
--       screen which has them in memory. But push notifications carry
--       only the CONVERSATION id (reference_type='conversation',
--       reference_id={conversation_id}), so the push handler can't
--       call the existing RPC. Result: tick stayed single until the
--       recipient opened the chat screen, which only fires the
--       message-level RPC after the chat list loads. The user sees
--       the double tick "ticks twice when you enter the app" rather
--       than when the notification actually arrives.
--
--  WHAT: One SECURITY DEFINER RPC. Takes a conversation_id, validates
--        the caller is a participant, bulk-updates every undelivered
--        message addressed to the caller in that conversation. The
--        push_service foreground handler + the tap-from-background
--        deep-link can call this directly off the notification
--        payload without knowing message ids.
--
--  IDEMPOTENT: yes — CREATE OR REPLACE; UPDATE skips already-delivered
--              rows so re-firing the RPC is harmless.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.mark_conversation_delivered(
  p_conversation_id BIGINT
)
RETURNS INTEGER AS $$
DECLARE
  v_user UUID := auth.uid();
  v_count INTEGER;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to mark messages delivered.';
  END IF;

  UPDATE public.messages m
     SET delivered_at = NOW()
    FROM public.conversations c
   WHERE m.conversation_id = p_conversation_id
     AND m.conversation_id = c.id
     AND m.sender_id <> v_user
     AND m.delivered_at IS NULL
     AND (c.participant_a_id = v_user OR c.participant_b_id = v_user);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.mark_conversation_delivered(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_conversation_delivered(BIGINT) TO authenticated;
