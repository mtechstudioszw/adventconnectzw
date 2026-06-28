-- =====================================================================
--  PATCH 134 — cosmetic "verified admin" gold tick
--
--  Adds profiles.is_verified_admin: TRUE when a user is the super admin OR an
--  approved church admin. It drives a gold verified tick next to their name
--  across the app so members (and non-members) can see who runs a church.
--
--  ⚠️ COSMETIC ONLY. This flag grants NO privileges whatsoever. Every
--  privileged action (approving events / church claims, the admin screens,
--  setting flags) is gated by assert_super_admin() / is_super_admin(), which
--  read ONLY profiles.is_super_admin. A church admin having is_verified_admin
--  = TRUE does NOT give them any super-admin power. No RLS policy references
--  this column.
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_verified_admin boolean NOT NULL DEFAULT false;

-- profiles has column-level SELECT grants (patch_132): new columns are hidden
-- until explicitly granted. Expose the tick flag (it's not sensitive).
GRANT SELECT (is_verified_admin) ON public.profiles TO authenticated;

-- Recompute the flag for one user from its sources.
CREATE OR REPLACE FUNCTION public.recompute_verified_admin(p_uid uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.profiles p
     SET is_verified_admin = (
       COALESCE(p.is_super_admin, false)
       OR EXISTS (
         SELECT 1 FROM public.church_admins ca
          WHERE ca.user_id = p_uid AND ca.status = 'approved'
       )
     )
   WHERE p.id = p_uid;
$$;

-- Keep it current as church-admin rows are approved / changed / removed.
CREATE OR REPLACE FUNCTION public.trg_church_admin_verify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    PERFORM public.recompute_verified_admin(OLD.user_id);
    RETURN OLD;
  END IF;
  PERFORM public.recompute_verified_admin(NEW.user_id);
  IF (TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id) THEN
    PERFORM public.recompute_verified_admin(OLD.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_church_admins_verify ON public.church_admins;
CREATE TRIGGER trg_church_admins_verify
  AFTER INSERT OR UPDATE OR DELETE ON public.church_admins
  FOR EACH ROW EXECUTE FUNCTION public.trg_church_admin_verify();

-- Keep it current when the super-admin flag flips. BEFORE trigger sets NEW
-- inline (no recursive UPDATE).
CREATE OR REPLACE FUNCTION public.trg_profile_super_admin_verify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.is_super_admin IS DISTINCT FROM OLD.is_super_admin) THEN
    NEW.is_verified_admin := (
      COALESCE(NEW.is_super_admin, false)
      OR EXISTS (
        SELECT 1 FROM public.church_admins ca
         WHERE ca.user_id = NEW.id AND ca.status = 'approved'
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_super_admin_verify ON public.profiles;
CREATE TRIGGER trg_profiles_super_admin_verify
  BEFORE UPDATE OF is_super_admin ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.trg_profile_super_admin_verify();

-- Backfill everyone (sets your super-admin account's tick too).
UPDATE public.profiles p
   SET is_verified_admin = (
     COALESCE(p.is_super_admin, false)
     OR EXISTS (
       SELECT 1 FROM public.church_admins ca
        WHERE ca.user_id = p.id AND ca.status = 'approved'
     )
   );
