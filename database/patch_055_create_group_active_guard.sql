-- =====================================================================
--  PATCH 055 — Gate create_group to active (non-banned) users
--
--  create_group is SECURITY DEFINER, so it bypasses the conversations
--  insert RLS that elsewhere enforces public.user_is_active(). Add the
--  same guard here so banned/suspended accounts can't spin up groups.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_group(
  p_name        TEXT,
  p_photo_url   TEXT,
  p_description TEXT,
  p_member_ids  UUID[]
) RETURNS BIGINT AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_id   BIGINT;
  v_name TEXT := NULLIF(btrim(COALESCE(p_name, '')), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.user_is_active() THEN
    RAISE EXCEPTION 'Your account cannot create groups.';
  END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Group name is required.'; END IF;

  INSERT INTO public.conversations (
    is_group, name, photo_url, description, created_by, last_message_at
  ) VALUES (
    TRUE, v_name,
    NULLIF(btrim(COALESCE(p_photo_url, '')), ''),
    NULLIF(btrim(COALESCE(p_description, '')), ''),
    v_uid, now()
  ) RETURNING id INTO v_id;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_id, v_uid, 'admin');

  IF p_member_ids IS NOT NULL THEN
    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    SELECT v_id, uid, 'member'
      FROM unnest(p_member_ids) AS uid
     WHERE uid <> v_uid
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
