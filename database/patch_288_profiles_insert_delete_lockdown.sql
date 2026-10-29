-- =====================================================================
--  PATCH 288 — close the delete-and-reinsert self-grant on profiles,
--              and fix the yearly plan being graded Plus
--  STATUS: APPLIED 29 Oct 2026 (by the owner, verified)
--
--  Found 29 Oct 2026 while studying the app for Premium.
--
--  1. THE HOLE
--     profiles_block_privilege_self_grant() runs BEFORE UPDATE only. But
--     `authenticated` holds table-level INSERT and DELETE on profiles, and
--     RLS allows both on your own row (profiles_delete_self,
--     profiles_insert_self). So a member could:
--        DELETE FROM profiles WHERE id = auth.uid();
--        INSERT INTO profiles (id, is_super_admin, is_verified,
--                              premium_until, account_type, ...)
--        VALUES (auth.uid(), true, true, '2099-01-01', 'super_admin', ...);
--     and is_super_admin() reads exactly that column — full admin power,
--     a gold tick, free Premium, or a ban shaken off. Not seen exploited
--     (every super admin is accounted for), but it was open.
--
--     Fix, two layers:
--       a) Members can no longer DELETE their profile row. The app never
--          does: account deletion goes through the delete-account edge
--          function with the service role (which bypasses grants and RLS).
--       b) The guard now also runs BEFORE INSERT. A signed-in caller's new
--          row always starts with every privileged column at its default.
--          INSERT itself must stay granted — AuthService.updateProfile
--          upserts (INSERT ... ON CONFLICT DO UPDATE), which needs it.
--     Also restores the premium_tier snap-back on UPDATE that patch_268
--     added and a later rebuild of this function dropped. (Not exploitable
--     on its own — there is no UPDATE grant on premium_tier — but this
--     function is meant to be the complete list.)
--
--  2. THE YEARLY PLAN
--     premium_tier_for_base_plan() knew the US$30/year plan as 'annual'.
--     Play Console created it as 'annualpermanent' (see BillingConfig), so
--     a yearly Pro subscriber would have been graded Plus — 100 AI
--     questions instead of 500. No one has bought it yet (0 active
--     subscriptions), so no one was short-changed. Existing rows are
--     re-synced below anyway.
--
--  CLAUDE.md checklist: no new profiles column; this IS the guard, re-read
--  in full from the live database before writing; BEFORE trigger on
--  INSERT/UPDATE only, so the RETURN COALESCE(NEW, OLD) rule does not
--  arise (NEW is never NULL here).
-- =====================================================================

BEGIN;

-- 1a. No self-delete --------------------------------------------------
DROP POLICY IF EXISTS profiles_delete_self ON public.profiles;
REVOKE DELETE ON public.profiles FROM anon, authenticated;

-- 1b. The guard, in full ----------------------------------------------
CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  -- No JWT = the service role (edge functions) or a DB-internal caller
  -- such as handle_new_user(). The only path allowed to grant anything.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- patch 288: a row a signed-in caller INSERTS starts with nothing.
  -- Applies to super admins too: RLS only lets anyone insert their OWN
  -- row, and there is no legitimate reason to insert yourself as admin.
  IF TG_OP = 'INSERT' THEN
    NEW.is_super_admin    := FALSE;
    NEW.is_verified       := FALSE;
    NEW.is_verified_admin := FALSE;
    NEW.is_banned         := FALSE;
    NEW.is_business       := FALSE;
    NEW.account_type      := 'member';
    NEW.premium_until     := NULL;
    NEW.premium_tier      := NULL;
    RETURN NEW;
  END IF;

  -- Premium is BOUGHT, never self-assigned, so it covers super admins
  -- too — this is the one privilege they may not hand themselves.
  -- Both columns: premium_until says whether, premium_tier says which.
  NEW.premium_until := OLD.premium_until;
  NEW.premium_tier  := OLD.premium_tier;

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

  -- patch 267: account_type's CHECK allows 'super_admin'.
  NEW.account_type   := OLD.account_type;

  -- `is_business` can move TRUE during the auto-approve RPC; otherwise
  -- snap it back to whatever it was before.
  IF current_setting('app.auto_approving_business', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_business := OLD.is_business;
  END IF;

  -- patch 188: the gold tick is DERIVED, never self-assigned.
  -- recompute_verified_admin() raises this flag for the duration of its
  -- own transaction; every other caller gets snapped back. The flag is
  -- transaction-local (set_config's third argument), so it cannot leak
  -- into another statement or another session.
  IF current_setting('app.recomputing_verified_admin', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_verified_admin := OLD.is_verified_admin;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_profiles_block_self_grant ON public.profiles;
CREATE TRIGGER trg_profiles_block_self_grant
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_block_privilege_self_grant();

-- 2. The yearly plan ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.premium_tier_for_base_plan(p_plan text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    -- 'annualpermanent' is the yearly plan's real id in Play Console
    -- (patch 288). 'annual' stays for safety; nothing has used it.
    WHEN p_plan IN ('pro-monthly', 'annualpermanent', 'annual') THEN 'pro'
    -- Everything else, INCLUDING NULL, is the lowest paid tier, so an
    -- unrecognised plan under-grants rather than over-grants.
    ELSE 'plus'
  END;
$function$;

-- Re-grade anyone who already holds a subscription row.
SELECT public.sync_premium_until(s.user_id)
  FROM (SELECT DISTINCT user_id FROM public.subscriptions) s;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---------------------------------------------------------------------
--  Check it worked (run after the patch; read-only). Expect:
--    can_delete = false, delete_policy = 0,
--    trigger fires on INSERT OR UPDATE, yearly = pro
-- ---------------------------------------------------------------------
-- SELECT
--   has_table_privilege('authenticated', 'public.profiles', 'DELETE') AS can_delete,
--   (SELECT count(*) FROM pg_policies
--     WHERE tablename = 'profiles' AND cmd = 'DELETE') AS delete_policy,
--   (SELECT pg_get_triggerdef(oid) FROM pg_trigger
--     WHERE tgname = 'trg_profiles_block_self_grant') AS trigger_def,
--   public.premium_tier_for_base_plan('annualpermanent') AS yearly;
