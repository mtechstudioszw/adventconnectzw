-- =====================================================================
--  PATCH 113 — invite link: don't announce "joined via link" when the
--  tapper is ALREADY an active member.
--
--  Tapping an invite for a group you're already in re-ran the join and
--  posted "X joined via link" every time. Now we only post the system
--  message for a genuine (re)join; an existing active member just gets the
--  conversation id back so the app opens the group normally.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_conv    BIGINT;
  v_name    TEXT;
  v_already BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  SELECT conversation_id INTO v_conv
    FROM public.group_invites WHERE token = p_token;
  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'This invite link is invalid or has expired.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.conversation_removed_members
              WHERE conversation_id = v_conv AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'You were removed from this group and can''t rejoin with a link. Ask an admin to add you.';
  END IF;

  -- Already an ACTIVE member? Then just open the group — no re-join noise.
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members
     WHERE conversation_id = v_conv AND user_id = auth.uid()
       AND left_at IS NULL
  ) INTO v_already;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_conv, auth.uid(), 'member')
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET left_at = NULL;

  IF NOT v_already THEN
    SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone') INTO v_name
      FROM public.profiles WHERE id = auth.uid();
    PERFORM public._group_system_message(v_conv, auth.uid(),
      v_name || ' joined via link');
  END IF;

  RETURN v_conv;
END;
$function$;
