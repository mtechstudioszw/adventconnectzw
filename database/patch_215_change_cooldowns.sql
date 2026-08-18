-- =====================================================================
--  PATCH 215 — Church cooldown 90d → 14d, and the same gate on country
--
--  Two founder decisions, 18 Aug 2026:
--
--   1. The home-church cooldown from patch_069 was 90 days. Too blunt:
--      the anti group-hopping goal is served by any gate that makes
--      switching deliberate, and 90 days punished the ordinary cases —
--      someone who moved house, or who tapped the wrong church in a list
--      of 2,600 and noticed a month later. Now 14 days.
--
--   2. `country` (patch_213) gets the same 14-day gate. It is no longer
--      cosmetic: country scopes the feed, the marketplace and jobs, so an
--      ungated country field is a free "show me another country's
--      listings" switch, and cross-border listings are exactly what the
--      scoping exists to prevent.
--
--  --------------------------------------------------------------------
--  CLAUDE.md `profiles` CHECKLIST — worked, not assumed:
--
--   1. profiles_block_privilege_self_grant() — NOT touched, deliberately.
--      Country and church are self-declared identity, not privilege; the
--      whole point is that a member sets them for themselves. Adding
--      either there would break onboarding and edit-profile.
--
--   2. Explicit grants for the new `country_changed_at`? NO — and that is
--      the safe direction, not an oversight:
--        * No UPDATE grant. The TRIGGER stamps this column; the client
--          never names it in an UPDATE, and column-level UPDATE is checked
--          against the statement's columns, not what a trigger assigns.
--          Withholding it is what makes the clock unforgeable.
--        * No SELECT grant, matching `church_changed_at`, which has never
--          had one. The member learns when they can next change from the
--          trigger's exception message, which carries the date. Granting
--          SELECT would publish "when did this person last move country"
--          to every profile reader for no feature that asks for it.
--
--   3. Column-level REVOKE is ignored while a table grant exists — not
--      applicable, this patch only adds a column and replaces functions.
--
--   4. BEFORE triggers covering DELETE must RETURN COALESCE(NEW, OLD) —
--      both triggers here are BEFORE UPDATE only, so NEW is never NULL.
--      Do not widen either to DELETE without revisiting that.
--  --------------------------------------------------------------------
--
--  IDEMPOTENT: yes. ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
--  DROP TRIGGER IF EXISTS before CREATE TRIGGER.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Home church — same trigger as patch_069, 14 days instead of 90
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_church_change_cooldown()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.church_id IS DISTINCT FROM OLD.church_id THEN
    -- Cooldown check uses the STORED (OLD) clock — a client can't pass a
    -- forged NEW.church_changed_at to slip past it.
    IF OLD.church_id IS NOT NULL
       AND OLD.church_changed_at IS NOT NULL
       AND OLD.church_changed_at > now() - INTERVAL '14 days' THEN
      RAISE EXCEPTION 'You can only change your home church once every 2 weeks. Next change available after %.',
        to_char(OLD.church_changed_at + INTERVAL '14 days', 'Mon DD, YYYY');
    END IF;
    NEW.church_changed_at := now();   -- trigger sets it, not the client
  ELSE
    -- church_id unchanged: forbid hand-editing the cooldown clock (the
    -- bypass where you reset church_changed_at to the past, THEN switch
    -- church). Force it back to the stored value.
    NEW.church_changed_at := OLD.church_changed_at;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ---------------------------------------------------------------------
--  2. Country — the same shape, 14 days
--
--  FIRST SET IS ALWAYS FREE, and that matters more here than it did for
--  church. patch_213 backfilled every pre-existing profile to 'ZW' —
--  that was OUR guess, not the member's choice. Those rows have
--  country_changed_at NULL, so the guard below lets each of them correct
--  it once without waiting. New members are NULL until onboarding writes
--  their first country, which is likewise free.
-- ---------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS country_changed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.enforce_country_change_cooldown()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.country IS DISTINCT FROM OLD.country THEN
    IF OLD.country IS NOT NULL
       AND OLD.country_changed_at IS NOT NULL
       AND OLD.country_changed_at > now() - INTERVAL '14 days' THEN
      RAISE EXCEPTION 'You can only change your country once every 2 weeks. Next change available after %.',
        to_char(OLD.country_changed_at + INTERVAL '14 days', 'Mon DD, YYYY');
    END IF;
    NEW.country_changed_at := now();
  ELSE
    -- Same anti-bypass as church: without this you could rewind the clock
    -- in one statement and change country in the next.
    NEW.country_changed_at := OLD.country_changed_at;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_country_change_cooldown ON public.profiles;
CREATE TRIGGER trg_country_change_cooldown
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_country_change_cooldown();

-- ---------------------------------------------------------------------
--  3. Verification — run these and read the output.
-- ---------------------------------------------------------------------
-- SELECT tgname FROM pg_trigger
--  WHERE tgrelid = 'public.profiles'::regclass AND NOT tgisinternal
--  ORDER BY tgname;
--   -- expect both trg_church_change_cooldown and trg_country_change_cooldown
--
-- SELECT prosrc LIKE '%14 days%' AS church_is_14d
--   FROM pg_proc WHERE proname = 'enforce_church_change_cooldown';
--   -- expect: t
--
-- SELECT count(*) AS profiles_free_to_change_country
--   FROM public.profiles WHERE country_changed_at IS NULL;
--   -- expect: every row — nobody has spent their first change yet
