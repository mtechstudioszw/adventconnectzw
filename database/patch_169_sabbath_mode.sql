-- =====================================================================
--  PATCH 169 — Sabbath mode
--
--  Mute non-essential notifications from Friday sundown to Saturday
--  sundown. No other messaging app can ship this, and it is the most
--  Adventist feature available to the product.
--
--  DESIGN NOTE — why a timestamp and not a province:
--  Sundown depends on latitude, longitude and day-of-year. That maths
--  already exists, correct and tested, in `lib/services/sabbath_service.dart`.
--  Re-implementing solar declination in plpgsql to run per notification
--  would be slow and a second source of truth that could disagree with
--  what the user sees on their own home screen.
--
--  So the CLIENT computes its own Sabbath window and stamps
--  `sabbath_quiet_until`. The server only has to answer "is now before
--  that timestamp", which is trivial and always agrees with the app.
--
--  The guard is a BEFORE INSERT trigger on `notifications` rather than
--  an edit to each of patch_006's five notify functions: one guard
--  covers every existing source AND every future one, and returning NULL
--  drops the row before it exists, so no push is sent either.
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sabbath_mode_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sabbath_quiet_until  TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.sabbath_mode_enabled IS
  'User opted into muting non-essential notifications over the Sabbath.';

COMMENT ON COLUMN public.profiles.sabbath_quiet_until IS
  'End of the current Sabbath window (Saturday sundown), stamped by the '
  'client from SabbathService. Server compares against now() only — it '
  'never computes sundown itself.';

-- Notification types that ALWAYS deliver, Sabbath or not.
--   * obituary / urgent  — a death or an emergency in the congregation is
--                          precisely when people need to hear from church.
--   * message / friend   — person-to-person contact. Adventists talk on
--                          Sabbath; silencing a direct message would read
--                          as the app being broken, not reverent.
-- Everything else (likes, comments, marketplace, new videos, event
-- reminders, general announcements) waits until sundown Saturday.
CREATE OR REPLACE FUNCTION public.is_essential_notification(p_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_type, '') IN (
    'announcement_obituary',
    'announcement_urgent',
    'message',
    'friend_request',
    'friend_accepted'
  );
$$;

CREATE OR REPLACE FUNCTION public.suppress_sabbath_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  quiet BOOLEAN;
BEGIN
  IF public.is_essential_notification(NEW.type) THEN
    RETURN NEW;
  END IF;

  SELECT p.sabbath_mode_enabled
           AND p.sabbath_quiet_until IS NOT NULL
           AND now() < p.sabbath_quiet_until
    INTO quiet
    FROM public.profiles p
   WHERE p.id = NEW.user_id;

  -- Dropping the row (RETURN NULL) rather than flagging it: a muted
  -- notification the user never asked to see later is noise, and this
  -- also stops the push, which is the whole point.
  IF COALESCE(quiet, FALSE) THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_suppress_sabbath_notifications ON public.notifications;
CREATE TRIGGER trg_suppress_sabbath_notifications
  BEFORE INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.suppress_sabbath_notifications();

-- Partial index: the guard reads these two columns for every notification
-- insert, but only opted-in users matter.
CREATE INDEX IF NOT EXISTS idx_profiles_sabbath_quiet
  ON public.profiles (id, sabbath_quiet_until)
  WHERE sabbath_mode_enabled = TRUE;
