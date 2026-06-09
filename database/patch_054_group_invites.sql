-- =====================================================================
--  PATCH 054 — Group invite links
--
--  One reusable invite token per group (WhatsApp-style). Any MEMBER can
--  fetch/create it; any signed-in user who opens it joins as a member.
--  Depends on patch_052/053.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.group_invites (
  token           TEXT PRIMARY KEY,
  conversation_id BIGINT NOT NULL
    REFERENCES public.conversations(id) ON DELETE CASCADE,
  created_by      UUID NOT NULL REFERENCES public.profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS group_invites_conversation_idx
  ON public.group_invites (conversation_id);
ALTER TABLE public.group_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS group_invites_select ON public.group_invites;
CREATE POLICY group_invites_select ON public.group_invites
  FOR SELECT USING (public.is_conversation_member(conversation_id));

-- Fetch (or lazily create) the group's invite token. Members only.
CREATE OR REPLACE FUNCTION public.get_or_create_group_invite(p_conversation BIGINT)
RETURNS TEXT AS $$
DECLARE
  v_token TEXT;
BEGIN
  IF NOT public.is_conversation_member(p_conversation) THEN
    RAISE EXCEPTION 'Only group members can share the invite link.';
  END IF;
  SELECT token INTO v_token
    FROM public.group_invites
   WHERE conversation_id = p_conversation;
  IF v_token IS NULL THEN
    INSERT INTO public.group_invites (token, conversation_id, created_by)
    VALUES (replace(gen_random_uuid()::text, '-', ''), p_conversation, auth.uid())
    ON CONFLICT (conversation_id)
      DO UPDATE SET token = public.group_invites.token
    RETURNING token INTO v_token;
  END IF;
  RETURN v_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Join a group from an invite token. Returns the conversation id so the
-- app can open the chat.
CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token TEXT)
RETURNS BIGINT AS $$
DECLARE
  v_conv BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  SELECT conversation_id INTO v_conv
    FROM public.group_invites
   WHERE token = p_token;
  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'This invite link is invalid or has expired.';
  END IF;
  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_conv, auth.uid(), 'member')
  ON CONFLICT DO NOTHING;
  RETURN v_conv;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.get_or_create_group_invite(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_group_via_invite(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_or_create_group_invite(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_group_via_invite(TEXT) TO authenticated;
