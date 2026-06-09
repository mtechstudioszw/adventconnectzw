-- =====================================================================
--  PATCH 062 — Global "mark all incoming delivered"
--
--  Delivery (✓✓) was only stamped while the Chats/chat screen was
--  mounted or on a foreground push. So a recipient who'd been offline a
--  long time, then reopened the app to a non-Chats tab, left the sender
--  on a single ✓. This flips EVERY undelivered incoming message (1:1 +
--  group) for the caller in one call — invoked on app resume/online.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.mark_all_incoming_delivered()
RETURNS VOID AS $$
  UPDATE public.messages m
     SET delivered_at = now()
   WHERE m.delivered_at IS NULL
     AND m.sender_id <> auth.uid()
     AND EXISTS (
       SELECT 1 FROM public.conversations c
        WHERE c.id = m.conversation_id
          AND (c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid()
               OR public.is_conversation_member(c.id))
     );
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.mark_all_incoming_delivered() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_all_incoming_delivered() TO authenticated;
