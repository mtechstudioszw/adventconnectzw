-- =====================================================================
--  PATCH 102 — enforce group membership + group-deleted at the data layer
--
--  Bugs:
--   * A member who LEFT or was REMOVED kept seeing NEW messages, because
--     the SELECT policy used is_conversation_member (no left_at check).
--   * After an admin "deleted" the group (conversations.deleted_at set)
--     members could still send, because no INSERT policy checked it.
--
--  Fix:
--   * SELECT: active members see all; left/removed members see only
--     messages up to their left_at (history stays, new is hidden).
--   * INSERT: sending to a deleted group is rejected for everyone.
-- =====================================================================

-- Active member sees all; left member sees only up to their left_at.
CREATE OR REPLACE FUNCTION public.can_view_group_message(
  p_conv BIGINT, p_created TIMESTAMPTZ)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members m
     WHERE m.conversation_id = p_conv
       AND m.user_id = auth.uid()
       AND (m.left_at IS NULL OR p_created <= m.left_at)
  );
$$;

CREATE OR REPLACE FUNCTION public.is_group_deleted(p_conv BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversations c
     WHERE c.id = p_conv AND c.deleted_at IS NOT NULL
  );
$$;

-- ---- SELECT: 1:1 participant OR (group: active, or left ≤ left_at) ----
DROP POLICY IF EXISTS messages_select_participant ON public.messages;
CREATE POLICY messages_select_participant ON public.messages
  FOR SELECT TO authenticated
  USING (
    (EXISTS (SELECT 1 FROM public.conversations c
              WHERE c.id = messages.conversation_id
                AND (auth.uid() = c.participant_a_id
                     OR auth.uid() = c.participant_b_id)))
    OR public.can_view_group_message(conversation_id, created_at)
  );

-- ---- INSERT: 1:1 (unblocked) OR active group member of a live group ----
DROP POLICY IF EXISTS messages_insert_sender ON public.messages;
CREATE POLICY messages_insert_sender ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    (auth.uid() = sender_id) AND user_is_active() AND (
      ((EXISTS (SELECT 1 FROM public.conversations c
                 WHERE c.id = messages.conversation_id
                   AND (auth.uid() = c.participant_a_id
                        OR auth.uid() = c.participant_b_id)))
       AND (NOT is_conversation_blocked(conversation_id)))
      OR (is_active_conversation_member(conversation_id)
          AND NOT public.is_group_deleted(conversation_id))
    )
  );
