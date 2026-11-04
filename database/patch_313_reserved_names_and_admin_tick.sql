-- patch_313 — Reserved names for member profiles; super admins always
-- carry the gold tick (owner, 4 Nov 2026).
--
-- 1. Anyone could rename themselves "Adventist Super App Team" (or
--    "… Official", "General Conference", "ADRA" …) and pass as the app or a
--    church body. Pages were already protected (page_name_is_protected);
--    member profiles were not. Now:
--      * a member renaming to a reserved name is refused with a message;
--      * a NEW account arriving with one (sign-up metadata, Google name)
--        is saved as "Member" instead of failing the sign-up;
--      * usernames starting with adventistsuperapp / adventconnect /
--        official are refused the same way.
--    Super admins are exempt — the official account IS "Adventist Super
--    App Team".
--
-- 2. A super admin always has is_verified = true. Safe: is_super_admin
--    itself can only be set by the server or another super admin
--    (profiles_block_privilege_self_grant snaps it back for everyone
--    else, and this trigger fires AFTER that one — triggers run in name
--    order, "trg_profiles_block_self_grant" < "trg_profiles_reserved…").
--
-- Checklist (CLAUDE.md): no new column, no new grant needed; INSERT/UPDATE
-- only, so RETURN NEW is correct (no DELETE).

CREATE OR REPLACE FUNCTION public.profiles_reserved_name_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
DECLARE
  v_user_reserved boolean;
BEGIN
  IF coalesce(NEW.is_super_admin, false) THEN
    NEW.is_verified := true;
    RETURN NEW;
  END IF;

  IF (TG_OP = 'INSERT' OR NEW.full_name IS DISTINCT FROM OLD.full_name)
     AND public.page_name_is_protected(coalesce(NEW.full_name, '')) THEN
    IF TG_OP = 'INSERT' THEN
      NEW.full_name := 'Member';
    ELSIF auth.uid() IS NOT NULL THEN
      RAISE EXCEPTION 'That name is reserved for official accounts. Please use your own name.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_user_reserved := lower(coalesce(NEW.username, '')) ~ '^(adventistsuperapp|adventconnect|official|superapp|sda_?official)';
  IF v_user_reserved
     AND (TG_OP = 'INSERT' OR NEW.username IS DISTINCT FROM OLD.username) THEN
    IF TG_OP = 'INSERT' THEN
      NEW.username := NULL;
    ELSIF auth.uid() IS NOT NULL THEN
      RAISE EXCEPTION 'That username is reserved for official accounts.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_reserved_name ON public.profiles;
CREATE TRIGGER trg_profiles_reserved_name
  BEFORE INSERT OR UPDATE OF full_name, username, is_super_admin, is_verified
  ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_reserved_name_guard();
