-- =====================================================================
--  PATCH 085 — per-user message visibility floor
--
--  The earliest message a user should see in a conversation is the LATEST
--  of:
--    * their cleared_at (Clear chat, patch_081),
--    * their group join time (conversation_members.joined_at) — so a new
--      member doesn't see history from before they joined,
--    * for church groups (implicit membership), when they joined the
--      church (profiles.church_changed_at).
--  greatest() ignores NULLs, so a 1:1 chat with no clear returns NULL
--  (no floor). The client filters fetched messages to created_at > floor.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.message_floor(p_conv BIGINT)
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT greatest(
    (SELECT cs.cleared_at FROM public.conversation_state cs
      WHERE cs.user_id = auth.uid() AND cs.conversation_id = p_conv),
    (SELECT cm.joined_at FROM public.conversation_members cm
      WHERE cm.user_id = auth.uid() AND cm.conversation_id = p_conv),
    (SELECT pr.church_changed_at
       FROM public.conversations c
       JOIN public.profiles pr ON pr.id = auth.uid()
      WHERE c.id = p_conv AND c.church_id IS NOT NULL)
  );
$$;
GRANT EXECUTE ON FUNCTION public.message_floor(BIGINT) TO authenticated;
