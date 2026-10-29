-- =====================================================================
--  PATCH 290 — Page safety
--  STATUS: APPLIED 29 Oct 2026 (by the owner, verified)
--
--  The second half of the Friends/Follow plan the owner approved ("build
--  both", 29 Oct 2026). Pages can be followed by anyone and can post
--  publicly, which makes them the easiest thing in the app to abuse —
--  a fake "Seventh-day Adventist Church" Page collecting tithes, or a
--  burst of throwaway Pages for spam. What this adds:
--
--    1. Protected names. Official names (the national Church, the GC,
--       division and unions, ADRA, Hope Channel, the White Estate, this
--       app, and the word "official") can only
--       be used by a VERIFIED Page — a super admin verifies, or the
--       owner earns the gold tick (patch 289). A new Page with one is
--       refused with a message saying how to get verified.
--    2. A real account first: 14 days old and a confirmed email before
--       creating a Page.
--    3. One new Page per week per member (the 3-Page total stays).
--    4. At most 10 admins/editors per Page.
--    (Report Page already exists — patch 275's report sheet.)
--
--  Super admins and the service role are exempt from all of it.
--  Checked first: 0 Pages exist, so nothing already live is affected.
--
--  CLAUDE.md checklist: no profiles change. pages_guard is re-stated IN
--  FULL from the live definition with the new rules added; it now runs
--  SECURITY DEFINER so it can read auth.users.email_confirmed_at and
--  count the member's Pages regardless of RLS. BEFORE triggers here are
--  INSERT/UPDATE only and return COALESCE(NEW, OLD).
-- =====================================================================

BEGIN;

-- Lower-case, punctuation folded to spaces, so "S.D.A." and "sda" match.
CREATE OR REPLACE FUNCTION public.page_name_key(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  -- Dots and apostrophes are dropped first, so "S.D.A." folds to "sda"
  -- rather than "s d a" (which would slip past every phrase).
  SELECT ' ' || trim(regexp_replace(
                       regexp_replace(lower(coalesce(p_name, '')),
                                      '[.''’]', '', 'g'),
                       '[^a-z0-9]+', ' ', 'g')) || ' ';
$function$;

-- Phrases only a verified Page may carry. Matched as whole words inside
-- the folded name, so "Avondale SDA Choir" and "Mabvuku SDA Church" are
-- fine but "SDA Church Zimbabwe" and "ADRA Harare" are not.
CREATE OR REPLACE FUNCTION public.page_name_is_protected(p_name text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM unnest(ARRAY[
        -- National and world bodies. A LOCAL church ("Mabvuku SDA
        -- Church") is deliberately allowed: those are most Pages.
        ' seventh day adventist church zimbabwe ',
        ' sda church zimbabwe ',
        ' adventist church zimbabwe ',
        ' general conference ',
        ' adventist world church ',
        ' southern africa indian ocean division ',
        ' zimbabwe union ',
        ' zimbabwe east union ',
        ' zimbabwe west union ',
        ' zeuc ',
        ' zwuc ',
        ' adra ',
        ' adventist development and relief ',
        ' hope channel ',
        ' adventist world radio ',
        ' ellen g white estate ',
        ' white estate ',
        ' adventist review ',
        ' adventist super app ',
        ' adventconnect ',
        ' official '
      ]) AS phrase
     WHERE public.page_name_key(p_name) LIKE '%' || phrase || '%'
  );
$function$;

CREATE OR REPLACE FUNCTION public.pages_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_count int;
  v_joined timestamptz;
  v_confirmed timestamptz;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_super_admin() THEN
      NEW.is_verified := false;
      NEW.status := 'active';
      NEW.moderation_reason := NULL;
      NEW.created_by := auth.uid();
      SELECT count(*) INTO v_count FROM public.pages WHERE created_by = auth.uid();
      IF v_count >= 3 THEN
        RAISE EXCEPTION 'PAGE_LIMIT'
          USING ERRCODE = '42501',
                HINT = 'You can create up to 3 Pages.';
      END IF;

      -- patch 290: a real account first.
      SELECT p.created_at INTO v_joined FROM public.profiles p
       WHERE p.id = auth.uid();
      SELECT u.email_confirmed_at INTO v_confirmed FROM auth.users u
       WHERE u.id = auth.uid();
      IF v_joined IS NULL OR v_joined > now() - interval '14 days' THEN
        RAISE EXCEPTION 'PAGE_TOO_NEW'
          USING ERRCODE = '42501',
                HINT = 'Your account needs to be 14 days old to create a Page.';
      END IF;
      IF v_confirmed IS NULL THEN
        RAISE EXCEPTION 'PAGE_EMAIL'
          USING ERRCODE = '42501',
                HINT = 'Confirm your email address before creating a Page.';
      END IF;

      -- patch 290: one new Page a week.
      IF EXISTS (SELECT 1 FROM public.pages
                  WHERE created_by = auth.uid()
                    AND created_at > now() - interval '7 days') THEN
        RAISE EXCEPTION 'PAGE_WEEKLY'
          USING ERRCODE = '42501',
                HINT = 'You can create one Page a week.';
      END IF;

      -- patch 290: official names need a verified Page.
      IF public.page_name_is_protected(NEW.name) THEN
        RAISE EXCEPTION 'PAGE_NAME_PROTECTED'
          USING ERRCODE = '42501',
                HINT = 'That name is reserved for official, verified Pages.';
      END IF;
    END IF;
    NEW.created_at := now();
  ELSE
    IF auth.uid() IS NOT NULL AND NOT public.is_super_admin() THEN
      NEW.is_verified := OLD.is_verified;
      NEW.status := OLD.status;
      NEW.moderation_reason := OLD.moderation_reason;

      -- patch 290: renaming to an official name needs a verified Page.
      IF NEW.name IS DISTINCT FROM OLD.name
         AND NOT OLD.is_verified
         AND public.page_name_is_protected(NEW.name) THEN
        RAISE EXCEPTION 'PAGE_NAME_PROTECTED'
          USING ERRCODE = '42501',
                HINT = 'That name is reserved for official, verified Pages.';
      END IF;
    END IF;
    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;
  END IF;
  NEW.updated_at := now();
  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- At most 10 admins/editors per Page ------------------------------------
CREATE OR REPLACE FUNCTION public.page_admins_cap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  -- Serialise adds to one Page so two at once can't both pass.
  PERFORM pg_advisory_xact_lock(hashtext('page_admins:' || NEW.page_id::text));
  IF (SELECT count(*) FROM public.page_admins WHERE page_id = NEW.page_id) >= 10 THEN
    RAISE EXCEPTION 'PAGE_ADMIN_LIMIT'
      USING ERRCODE = '42501',
            HINT = 'A Page can have up to 10 admins and editors.';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS page_admins_cap_trg ON public.page_admins;
CREATE TRIGGER page_admins_cap_trg
  BEFORE INSERT ON public.page_admins
  FOR EACH ROW EXECUTE FUNCTION public.page_admins_cap();

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---------------------------------------------------------------------
--  Check it worked (read-only). Expect: true, false, true, a trigger.
-- ---------------------------------------------------------------------
-- SELECT public.page_name_is_protected('Seventh-day Adventist Church Harare') AS church,
--        public.page_name_is_protected('Avondale SDA Youth Choir') AS choir,
--        public.page_name_is_protected('ADRA Zimbabwe') AS adra,
--        (SELECT tgname FROM pg_trigger WHERE tgname = 'page_admins_cap_trg') AS cap;
