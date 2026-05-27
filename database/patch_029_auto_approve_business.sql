-- patch_029_auto_approve_business.sql
--
-- WHAT:  Remove the admin review step for business-account applications.
--        Anyone who submits the form gets `status = 'approved'` instantly
--        and `profiles.is_business` flipped to TRUE in the same call so
--        the rest of the app (marketplace claim flows, etc.) unlocks
--        without a round-trip to a human moderator.
--
-- WHY:   Founder direction (2026-05-27): business onboarding should be
--        self-serve, matching the existing self-serve seller flow added
--        in patch_022. The legacy admin queue is dropped.
--
-- HOW:   A SECURITY DEFINER RPC `apply_for_business_auto_approve` does
--        both writes in a single transaction. It bypasses:
--          - the `biz_apps_insert_self` RLS policy (which pins status to
--            'pending' on user inserts) by running as definer
--          - the `profiles_block_privilege_self_grant` trigger (which
--            snaps `is_business` back to OLD) via a session-local GUC
--            the trigger now honors
--
-- IDEMPOTENT:  yes — function and trigger are CREATE OR REPLACE.
--
-- =============================================================

-- --------------------------------------------------------------
-- 1. Update the privilege-snap-back trigger so it lets a self
--    update of `is_business` through *only* when the auto-approve
--    RPC is in flight (signalled via a session GUC).
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
RETURNS TRIGGER AS $$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.is_super_admin, FALSE)
    INTO caller_is_super
    FROM public.profiles p
    WHERE p.id = auth.uid();

  IF caller_is_super THEN
    RETURN NEW;
  END IF;

  NEW.is_super_admin := OLD.is_super_admin;
  NEW.is_verified    := OLD.is_verified;
  NEW.is_banned      := OLD.is_banned;

  -- `is_business` can move TRUE during the auto-approve RPC; otherwise
  -- snap it back to whatever it was before.
  IF current_setting('app.auto_approving_business', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_business := OLD.is_business;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;


-- --------------------------------------------------------------
-- 2. The RPC. Authenticated users may call it; it inserts an
--    approved application row + flips their profile flag.
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_for_business_auto_approve(
  p_business_name       TEXT,
  p_category            TEXT,
  p_description         TEXT DEFAULT NULL,
  p_applicant_whatsapp  TEXT DEFAULT NULL
)
RETURNS public.business_applications AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_row     public.business_applications;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in to apply for a business account.';
  END IF;

  INSERT INTO public.business_applications (
    user_id,
    business_name,
    category,
    description,
    applicant_whatsapp,
    status,
    reviewed_at,
    reviewer_note
  )
  VALUES (
    v_user_id,
    p_business_name,
    p_category,
    NULLIF(btrim(p_description), ''),
    NULLIF(btrim(p_applicant_whatsapp), ''),
    'approved',
    NOW(),
    'Auto-approved on submission.'
  )
  RETURNING * INTO v_row;

  -- Bypass the privilege-snap-back trigger for this one UPDATE.
  PERFORM set_config('app.auto_approving_business', 'true', true);
  UPDATE public.profiles
     SET is_business = TRUE
     WHERE id = v_user_id;
  PERFORM set_config('app.auto_approving_business', 'false', true);

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.apply_for_business_auto_approve(
  TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_for_business_auto_approve(
  TEXT, TEXT, TEXT, TEXT
) TO authenticated;


-- --------------------------------------------------------------
-- 3. Friend-request notifications. Fires AFTER INSERT on
--    `friendships` and writes a row into `notifications` for the
--    addressee with reference_type = 'friend_request' so the
--    push pipeline + in-app notification centre can route a tap
--    straight to the Requests tab in /messages.
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.friendships_notify_addressee()
RETURNS TRIGGER AS $$
DECLARE
  v_requester_name TEXT;
BEGIN
  IF NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), 'Someone')
    INTO v_requester_name
    FROM public.profiles p
    WHERE p.id = NEW.requester_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  VALUES (
    NEW.addressee_id,
    'New friend request',
    v_requester_name || ' sent you a friend request.',
    'friend_request',
    NEW.id::text,
    'friend_request'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_friendships_notify_addressee
  ON public.friendships;
CREATE TRIGGER trg_friendships_notify_addressee
  AFTER INSERT ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.friendships_notify_addressee();
