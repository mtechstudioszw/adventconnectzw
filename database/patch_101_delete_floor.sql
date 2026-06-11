-- =====================================================================
--  PATCH 101 — deleting a 1:1 conversation must floor its old messages
--
--  soft_delete_conversation records deleted_by_a_at / deleted_by_b_at, but
--  message_floor ignored them — so when the thread reappeared (the other
--  person messaged again, or you searched + reopened it) every old message
--  came back. The floor now also includes the caller's own delete
--  timestamp, so only messages sent AFTER the delete are shown.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.message_floor(p_conv BIGINT)
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT greatest(
    (SELECT cs.cleared_at FROM public.conversation_state cs
      WHERE cs.user_id = auth.uid() AND cs.conversation_id = p_conv),
    (SELECT cm.joined_at FROM public.conversation_members cm
      WHERE cm.user_id = auth.uid() AND cm.conversation_id = p_conv),
    (SELECT pr.church_changed_at
       FROM public.conversations c
       JOIN public.profiles pr ON pr.id = auth.uid()
      WHERE c.id = p_conv AND c.church_id IS NOT NULL),
    -- The caller's own "delete conversation" timestamp (per side).
    (SELECT CASE
              WHEN c.participant_a_id = auth.uid() THEN c.deleted_by_a_at
              WHEN c.participant_b_id = auth.uid() THEN c.deleted_by_b_at
            END
       FROM public.conversations c WHERE c.id = p_conv)
  );
$$;
