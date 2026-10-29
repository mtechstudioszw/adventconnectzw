-- ============================================================================
--  patch_282 — "Who can follow me": Everyone / Friends only / No one
--  STATUS: DRAFT — NOT APPLIED. Apply only on the owner's go-ahead.
-- ============================================================================
--
--  Owner (28 Oct 2026): personal accounts choose who may follow them;
--  Pages can always be followed. This applies to `follows` (people) only —
--  `page_follows` is untouched.
--
--    everyone  (default) — today's behaviour: public profiles are followed
--                          at once, private ones ask first.
--    friends             — only accepted friends can follow.
--    nobody              — nobody can follow.
--
--  Enforced in the database, not just by hiding a button: the existing
--  BEFORE INSERT trigger on `follows` refuses a follow the setting doesn't
--  allow (FOLLOW_NOT_ALLOWED), so an old app build or a hand-made request
--  can't get around it.
--
--  Switching to friends/nobody goes through set_who_can_follow(), which
--  also removes followers (and pending requests) that the new setting no
--  longer allows, and returns how many — the app warns before calling it.
--
--  Known limit: unfriending someone later does NOT remove their follow
--  under 'friends'. Re-saving the setting cleans it up. Kept out of scope
--  rather than adding a trigger to `friendships`.
--
--  CLAUDE.md checklist for profiles columns:
--    1. privilege trigger — who_can_follow is a member setting, not a
--       privilege; profiles_block_privilege_self_grant() needs no change.
--    2. explicit GRANT SELECT added (there is no table-level grant). No
--       UPDATE grant: the only way to change it is set_who_can_follow(),
--       so the follower clean-up can't be skipped.
--    3. no column-level REVOKE is relied on.
--    4. the BEFORE trigger changed here covers INSERT only and still
--       returns COALESCE(NEW, OLD).
-- ============================================================================

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS who_can_follow text NOT NULL DEFAULT 'everyone';

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_who_can_follow_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_who_can_follow_check
  CHECK (who_can_follow IN ('everyone', 'friends', 'nobody'));

GRANT SELECT (who_can_follow) ON public.profiles TO authenticated;

-- The gate on every new follow. Same function patch_274 created; the
-- status logic is unchanged, the setting check is new.
CREATE OR REPLACE FUNCTION public.follows_set_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_who text;
  v_private boolean;
BEGIN
  SELECT who_can_follow, is_private INTO v_who, v_private
    FROM public.profiles WHERE id = NEW.followee_id;

  IF v_who = 'nobody'
     OR (v_who = 'friends'
         AND NOT public.are_friends(NEW.follower_id, NEW.followee_id)) THEN
    RAISE EXCEPTION 'FOLLOW_NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  NEW.status := CASE WHEN COALESCE(v_private, false)
                     THEN 'pending' ELSE 'active' END;
  NEW.created_at := now();
  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Change your own setting; removes follows the new setting disallows.
CREATE OR REPLACE FUNCTION public.set_who_can_follow(p_value text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_removed integer := 0;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Sign in first.' USING ERRCODE = '42501';
  END IF;
  IF p_value NOT IN ('everyone', 'friends', 'nobody') THEN
    RAISE EXCEPTION 'Unknown setting.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles SET who_can_follow = p_value WHERE id = v_me;

  IF p_value = 'nobody' THEN
    DELETE FROM public.follows WHERE followee_id = v_me;
    GET DIAGNOSTICS v_removed = ROW_COUNT;
  ELSIF p_value = 'friends' THEN
    DELETE FROM public.follows
     WHERE followee_id = v_me
       AND NOT public.are_friends(follower_id, v_me);
    GET DIAGNOSTICS v_removed = ROW_COUNT;
  END IF;

  RETURN v_removed;
END;
$function$;

REVOKE ALL ON FUNCTION public.set_who_can_follow(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_who_can_follow(text) TO authenticated;

-- How many current followers a switch would remove — for the warning.
CREATE OR REPLACE FUNCTION public.followers_removed_by(p_value text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT CASE p_value
    WHEN 'nobody' THEN
      (SELECT count(*)::int FROM public.follows WHERE followee_id = auth.uid())
    WHEN 'friends' THEN
      (SELECT count(*)::int FROM public.follows
        WHERE followee_id = auth.uid()
          AND NOT public.are_friends(follower_id, auth.uid()))
    ELSE 0 END;
$function$;

REVOKE ALL ON FUNCTION public.followers_removed_by(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.followers_removed_by(text) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
