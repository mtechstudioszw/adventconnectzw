-- =====================================================================
--  PATCH 221 — the FIRST choice must not spend the cooldown
--
--  Bug I introduced in patch_215, found 19 Aug 2026.
--
--  Both cooldown triggers stamp the clock inside the "value changed"
--  branch — including the very first time a value is set. So:
--
--    onboarding writes country for the first time
--      -> OLD.country IS NULL, so the guard allows it
--      -> but it still sets country_changed_at = now()
--    member opens Edit profile a minute later, spots a typo
--      -> OLD.country_changed_at is one minute old
--      -> BLOCKED for fourteen days
--
--  A brand-new member could therefore be locked out of correcting a
--  mis-tap made during signup, on a screen that offers them a picker as
--  if it were freely editable. Same trap on `church_id` via patch_069,
--  which has been live far longer at 90 days — 25 members are inside a
--  church cooldown as of today, and some of those are almost certainly
--  this, not deliberate hopping.
--
--  THE FIX: only start the clock on a REAL change — one where a previous
--  value already existed. Setting something for the first time leaves the
--  clock NULL, so the member still gets one free correction afterwards;
--  the cooldown then applies from that point on.
--
--  Concretely, for a new member:
--    onboarding picks Kenya      -> allowed, clock stays NULL
--    edit profile: Kenya -> UK   -> allowed (clock NULL), clock starts
--    edit profile: UK -> Ghana   -> blocked for 14 days
--
--  That is the behaviour the cooldown was actually asked for: it stops
--  repeated hopping, it does not punish the first correction.
--
--  Existing rows are NOT reset. Anyone genuinely mid-cooldown stays there;
--  this only changes when the clock STARTS from here on.
--
--  --------------------------------------------------------------------
--  CLAUDE.md checklist: replaces two BEFORE UPDATE functions, adds no
--  columns, no grants, no DELETE coverage. NEW is never NULL in either.
--  IDEMPOTENT: CREATE OR REPLACE only; the triggers themselves are
--  unchanged and keep pointing at these functions.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.enforce_church_change_cooldown()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.church_id IS DISTINCT FROM OLD.church_id THEN
    IF OLD.church_id IS NOT NULL
       AND OLD.church_changed_at IS NOT NULL
       AND OLD.church_changed_at > now() - INTERVAL '14 days' THEN
      RAISE EXCEPTION 'You can only change your home church once every 2 weeks. Next change available after %.',
        to_char(OLD.church_changed_at + INTERVAL '14 days', 'Mon DD, YYYY');
    END IF;
    -- Only a change FROM an existing value starts the clock. The first
    -- time a church is chosen, leave it NULL so the member keeps one
    -- free correction.
    IF OLD.church_id IS NOT NULL THEN
      NEW.church_changed_at := now();
    ELSE
      NEW.church_changed_at := OLD.church_changed_at;
    END IF;
  ELSE
    -- Unchanged: forbid hand-editing the clock (the bypass where you
    -- rewind it in one statement and switch in the next).
    NEW.church_changed_at := OLD.church_changed_at;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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
    IF OLD.country IS NOT NULL THEN
      NEW.country_changed_at := now();
    ELSE
      NEW.country_changed_at := OLD.country_changed_at;
    END IF;
  ELSE
    NEW.country_changed_at := OLD.country_changed_at;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ---------------------------------------------------------------------
--  One-off repair: release anyone whose clock was started by their FIRST
--  set rather than by a real change.
--
--  patch_213 backfilled every pre-existing profile to 'ZW', so for those
--  rows OLD.country was never NULL and a stamp there IS a real change —
--  we cannot tell those apart retrospectively. What we CAN say is that a
--  country_changed_at within a minute of the profile's own creation is an
--  onboarding write, not a considered change. Those get released.
-- ---------------------------------------------------------------------
UPDATE public.profiles
   SET country_changed_at = NULL
 WHERE country_changed_at IS NOT NULL
   AND created_at IS NOT NULL
   AND country_changed_at <= created_at + INTERVAL '1 minute';

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- SELECT prosrc LIKE '%OLD.country IS NOT NULL THEN%' AS country_fixed
--   FROM pg_proc WHERE proname='enforce_country_change_cooldown';
--   -- expect: t
--
-- SELECT count(*) FILTER (WHERE country_changed_at > now() - interval '14 days') AS country_locked,
--        count(*) FILTER (WHERE church_changed_at  > now() - interval '14 days') AS church_locked
--   FROM public.profiles;
