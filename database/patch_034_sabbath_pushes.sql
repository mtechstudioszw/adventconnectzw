-- =====================================================================
--  PATCH 034 — Sabbath approaching + Happy Sabbath push notifications
--
--  WHY: User spec (2026-05-31): "When the sabbath is abt to reach send
--       a notification saying sabbath is approaching, when it reach
--       send a notification saying happy sabbath with the user's name."
--
--  WHAT:
--    1. public.enqueue_sabbath_approaching() — runs every Friday at
--       17:00 Africa/Harare (15:00 UTC). Sends one push per
--       not-banned profile reading "Sabbath is approaching" so people
--       can wrap up their work before sundown.
--    2. public.enqueue_sabbath_begins() — runs every Friday at
--       18:00 Africa/Harare (16:00 UTC). Sends one personalised
--       "Happy Sabbath, <first name>" push.
--
--  WHY THE FIXED TIMES instead of true astronomical sunset:
--    Computing Friday sunset per user in PL/pgSQL means re-implementing
--    the NOAA solar equation against each profile's province — the
--    current iteration of the app keeps that calc client-side
--    (SabbathService). For the push, we pick a fixed Africa/Harare
--    time that brackets the actual Zimbabwean sunset year-round (sunset
--    in Harare varies between ~17:15 in mid-winter and ~18:30 in
--    mid-summer; 17:00 is always pre-sunset, 18:00 is always at or
--    just after). Good enough for "approaching" and "happy" semantics.
--    A future iteration can replace these crons with one that reads
--    per-user sunset off a server-computed table.
--
--  DEDUPE: NOT EXISTS check against the same (user, type, week) so a
--          cron re-run during the same window doesn't double-fire.
--          We key the dedupe by ISO week + year because Friday is in
--          the same ISO week as Saturday in PG conventions.
--
--  IDEMPOTENT: yes — CREATE OR REPLACE + DROP/RESCHEDULE.
-- =====================================================================


-- ----- 1. "Sabbath is approaching" -----------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_sabbath_approaching()
RETURNS INTEGER AS $$
DECLARE
  inserted_count INTEGER;
  iso_week_key TEXT := to_char(NOW() AT TIME ZONE 'Africa/Harare', 'IYYY-IW');
BEGIN
  WITH targets AS (
    SELECT p.id AS user_id
      FROM public.profiles p
     WHERE COALESCE(p.is_banned, FALSE) = FALSE
       AND NOT EXISTS (
         SELECT 1
           FROM public.notifications n
          WHERE n.user_id = p.id
            AND n.type = 'sabbath_approaching'
            AND n.reference_id = iso_week_key
       )
  )
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    t.user_id,
    'Sabbath is approaching',
    'Sundown is near. Wrap up and prepare for a blessed Sabbath.',
    'sabbath_approaching',
    iso_week_key,
    'sabbath'
  FROM targets t;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ----- 2. "Happy Sabbath, <first name>" ------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_sabbath_begins()
RETURNS INTEGER AS $$
DECLARE
  inserted_count INTEGER;
  iso_week_key TEXT := to_char(NOW() AT TIME ZONE 'Africa/Harare', 'IYYY-IW');
BEGIN
  WITH targets AS (
    SELECT
      p.id AS user_id,
      -- First word of full_name, fallback "friend" so the message
      -- never reads "Happy Sabbath, ."
      COALESCE(
        NULLIF(split_part(btrim(p.full_name), ' ', 1), ''),
        'friend'
      ) AS first_name
    FROM public.profiles p
    WHERE COALESCE(p.is_banned, FALSE) = FALSE
      AND NOT EXISTS (
        SELECT 1
          FROM public.notifications n
         WHERE n.user_id = p.id
           AND n.type = 'sabbath_begins'
           AND n.reference_id = iso_week_key
      )
  )
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    t.user_id,
    'Happy Sabbath, ' || t.first_name,
    'May your Sabbath be filled with rest, joy and worship.',
    'sabbath_begins',
    iso_week_key,
    'sabbath'
  FROM targets t;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ----- 3. Schedule both jobs ----------------------------------------
-- Wipe any prior schedule entries with the same names so re-running
-- this patch doesn't accumulate duplicates.
DO $$
BEGIN
  PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname IN ('enqueue_sabbath_approaching',
                      'enqueue_sabbath_begins');
END $$;

-- Friday 17:00 Africa/Harare = 15:00 UTC. cron expression DOW=5.
SELECT cron.schedule(
  'enqueue_sabbath_approaching',
  '0 15 * * 5',
  $$SELECT public.enqueue_sabbath_approaching();$$
);

-- Friday 18:00 Africa/Harare = 16:00 UTC.
SELECT cron.schedule(
  'enqueue_sabbath_begins',
  '0 16 * * 5',
  $$SELECT public.enqueue_sabbath_begins();$$
);
