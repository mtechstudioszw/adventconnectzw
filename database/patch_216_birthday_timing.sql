-- =====================================================================
--  PATCH 216 — birthdays arrive in the MORNING, once
--
--  Reported: "the app is late to send birthday notifications, it sends
--  when the birthday is about to end, about 5pm."
--
--  Two bugs, and the second is what the member actually sees:
--
--   1. WRONG TIME. The cron runs every 2 hours (patch_114) and the match
--      is on `now() AT TIME ZONE 'Africa/Harare'`. The Harare day starts
--      at 22:00 UTC, and there IS a cron tick at 22:00 UTC — so the very
--      first notification of every birthday fired at MIDNIGHT local. A
--      notification delivered at 00:00 is one nobody reads.
--
--   2. IT FIRED TWICE. The de-dup guard was a rolling
--      `created_at > now() - interval '20 hours'`. Twenty hours after the
--      midnight send is 20:00 the SAME local day — still the member's
--      birthday, so the loop sent the whole fan-out again in the evening.
--      That evening duplicate is the "late" notification being reported;
--      it was never late, it was a second copy.
--
--  Fixes: de-dup on the local CALENDAR DAY (a birthday is a once-a-day
--  event, so the window must be a day, not a rolling 20h), and hold the
--  send until 08:00 local so it lands when people are awake. The 2-hourly
--  cron stays: it is what catches somebody who fills in their date of
--  birth at 3pm, and the day-scoped guard makes extra ticks free.
--
--  NOT FIXED HERE, deliberately — 'Africa/Harare' is still the reference
--  clock for every member. That is wrong for a global app: an Australian
--  member's birthday is evaluated against Zimbabwe's calendar day. Fixing
--  it needs a per-member timezone, which the schema does not have —
--  `profiles.country` (patch_213) is the obvious input but a country is
--  not a timezone (the US spans six). Tracked, not guessed at.
--
--  IDEMPOTENT: yes — CREATE OR REPLACE, and the trailing catch-up send is
--  guarded by the same day-scoped de-dup.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_birthdays()
RETURNS void AS $$
DECLARE
  bday RECORD;
  friend_id UUID;
  local_now TIMESTAMP := now() AT TIME ZONE 'Africa/Harare';
BEGIN
  -- Nothing before 08:00 local. Without this the 22:00-UTC tick delivers
  -- every birthday at midnight, which is why the only copy anyone noticed
  -- was the evening one.
  IF EXTRACT(HOUR FROM local_now) < 8 THEN
    RETURN;
  END IF;

  FOR bday IN
    SELECT id, COALESCE(NULLIF(TRIM(full_name), ''), 'A member') AS name
    FROM public.profiles
    WHERE date_of_birth IS NOT NULL
      AND is_banned = FALSE
      AND EXTRACT(MONTH FROM date_of_birth) = EXTRACT(MONTH FROM local_now)
      AND EXTRACT(DAY   FROM date_of_birth) = EXTRACT(DAY   FROM local_now)
  LOOP
    -- Already done today? Scoped to the local calendar day, NOT a rolling
    -- 20 hours — that window was shorter than a day, so it reopened while
    -- it was still the same birthday and sent the whole fan-out twice.
    IF EXISTS (
      SELECT 1 FROM public.notifications
      WHERE type = 'birthday'
        AND reference_id = bday.id::text
        AND (created_at AT TIME ZONE 'Africa/Harare')
              >= date_trunc('day', local_now)
    ) THEN
      CONTINUE;
    END IF;

    -- The birthday person.
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    VALUES (bday.id, 'Happy Birthday! ' || chr(127874),
            'Wishing you a blessed birthday from everyone at Adventist Super App.',
            'birthday', bday.id::text, 'profile');

    -- Their accepted friends.
    FOR friend_id IN
      SELECT CASE WHEN requester_id = bday.id THEN addressee_id
                  ELSE requester_id END
      FROM public.friendships
      WHERE status = 'accepted'
        AND (requester_id = bday.id OR addressee_id = bday.id)
    LOOP
      INSERT INTO public.notifications
        (user_id, title, body, type, reference_id, reference_type)
      VALUES (friend_id,
              'It''s ' || bday.name || '''s birthday ' || chr(127874),
              'Send ' || bday.name || ' a birthday message today!',
              'birthday', bday.id::text, 'profile');
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- The old copy said "Advent Connect ZW" in the birthday person's own
-- message; the rebrand never reached this string. Fixed above.

-- Catch up anyone whose birthday is today and who has not been told yet.
SELECT public.notify_birthdays();

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- SELECT jobname, schedule, active FROM cron.job
--  WHERE jobname = 'birthday-notifications';
--   -- expect: 0 */2 * * *, active (unchanged — the fix is in the function)
--
-- SELECT prosrc LIKE '%date_trunc(''day'', local_now)%' AS day_scoped,
--        prosrc LIKE '%< 8%'                            AS morning_gate
--   FROM pg_proc WHERE proname = 'notify_birthdays';
--   -- expect: t, t
--
-- -- Nobody should hold two birthday rows for the same person on one day:
-- SELECT reference_id, user_id, count(*)
--   FROM public.notifications
--  WHERE type = 'birthday'
--    AND created_at > now() - interval '2 days'
--  GROUP BY 1, 2 HAVING count(*) > 1;
--   -- expect: no rows going forward (historical duplicates may remain)
