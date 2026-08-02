-- =====================================================================
--  PATCH 181 — "you haven't finished your profile" nudge
--
--  `notifications` has SELECT / UPDATE / DELETE policies for the owner
--  but NO INSERT policy — rows are created by triggers and server-side
--  functions only. That is the right design, so the nudge goes through a
--  SECURITY DEFINER RPC rather than opening the table to clients.
--
--  Deliberately conservative:
--    * It checks completeness SERVER-side. A client that lies about
--      being incomplete still gets nothing.
--    * It will not fire more than once every 14 days per user, so a
--      member who is simply not interested is asked occasionally, not
--      every launch.
--    * It returns the row count so the caller knows whether anything was
--      created, without needing to read the table back.
--
--  The AFTER INSERT trigger on `notifications` fans out to FCM, so this
--  reaches the device as a real push; the BEFORE INSERT Sabbath guard
--  (patch_169) still suppresses it during a member's quiet hours.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nudge_profile_incomplete()
RETURNS INTEGER
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me      UUID := auth.uid();
  v_missing INTEGER;
  v_name    TEXT;
BEGIN
  IF v_me IS NULL THEN
    RETURN 0;
  END IF;

  -- Don't nag: one nudge per fortnight, at most.
  IF EXISTS (
    SELECT 1 FROM public.notifications n
     WHERE n.user_id = v_me
       AND n.type = 'profile_incomplete'
       AND n.created_at > now() - INTERVAL '14 days'
  ) THEN
    RETURN 0;
  END IF;

  -- Same five checks the profile screen scores itself on.
  SELECT
    (CASE WHEN COALESCE(btrim(p.full_name), '')         = '' THEN 1 ELSE 0 END)
  + (CASE WHEN COALESCE(btrim(p.profile_photo_url), '') = '' THEN 1 ELSE 0 END)
  + (CASE WHEN COALESCE(btrim(p.bio), '')               = '' THEN 1 ELSE 0 END)
  + (CASE WHEN p.church_id     IS NULL                       THEN 1 ELSE 0 END)
  + (CASE WHEN p.date_of_birth IS NULL                       THEN 1 ELSE 0 END),
    COALESCE(NULLIF(btrim(p.full_name), ''), 'there')
    INTO v_missing, v_name
    FROM public.profiles p
   WHERE p.id = v_me;

  IF v_missing IS NULL OR v_missing = 0 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_type)
  VALUES (
    v_me,
    'Finish your profile',
    CASE
      WHEN v_missing = 1
        THEN 'One step left — add it so the community can find you.'
      ELSE 'You have ' || v_missing || ' steps left. A complete profile '
           || 'helps members recognise you.'
    END,
    'profile_incomplete',
    'profile'
  );

  RETURN 1;
END;
$$;

REVOKE ALL ON FUNCTION public.nudge_profile_incomplete() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nudge_profile_incomplete() TO authenticated;

COMMENT ON FUNCTION public.nudge_profile_incomplete() IS
  'Creates at most one profile_incomplete notification per user per 14 '
  'days, and only when the profile really is incomplete. Exists because '
  'notifications has no client INSERT policy, by design.';
