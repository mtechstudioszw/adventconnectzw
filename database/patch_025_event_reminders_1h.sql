-- =====================================================================
--  PATCH 025 — RSVP event reminders, 1h window
--
--  WHY: enqueue_event_reminders already pings RSVPed users 24h before
--       an event. Users asked for a second, closer reminder. Add a
--       1h window that fires on the same cron cadence (every 30
--       minutes — so anyone catching the next-30min boundary gets a
--       single ping). Dedupe by type+reference so a user never sees
--       two 1h reminders for the same event.
--
--  IDEMPOTENT: yes. CREATE OR REPLACE rewrites the function in place.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.enqueue_event_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inserted_count INTEGER := 0;
  next_count INTEGER;
BEGIN
  -- 24h window (existing behaviour)
  WITH due AS (
    SELECT
      e.id,
      e.title,
      ((e.start_date + COALESCE(NULLIF(e.start_time,'')::time, '09:00'::time))
        AT TIME ZONE 'Africa/Harare') AS start_at_utc
    FROM public.events e
    WHERE e.status = 'approved'
  ),
  pending AS (
    SELECT d.id, d.title, r.user_id
    FROM due d
    JOIN public.event_rsvps r
      ON r.event_id = d.id AND r.status = 'going'
    WHERE d.start_at_utc >  NOW() + INTERVAL '23 hours'
      AND d.start_at_utc <= NOW() + INTERVAL '24 hours'
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.user_id = r.user_id
          AND n.type = 'event_reminder'
          AND n.reference_id = d.id::text
      )
  )
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    p.user_id,
    'Event tomorrow',
    '"' || COALESCE(p.title,'An event you RSVPd to') ||
      '" starts in about 24 hours.',
    'event_reminder',
    p.id::text,
    'event'
  FROM pending p;
  GET DIAGNOSTICS next_count = ROW_COUNT;
  inserted_count := inserted_count + next_count;

  -- 1h window — fires on the next cron tick that lands inside the
  -- "starts within the next 60 minutes" interval. Cron runs every
  -- 30 minutes so each RSVPed user sees at most one 1h reminder.
  -- A separate type ('event_reminder_1h') keeps it independent of
  -- the 24h dedupe — both can fire for the same event.
  WITH due AS (
    SELECT
      e.id,
      e.title,
      ((e.start_date + COALESCE(NULLIF(e.start_time,'')::time, '09:00'::time))
        AT TIME ZONE 'Africa/Harare') AS start_at_utc
    FROM public.events e
    WHERE e.status = 'approved'
  ),
  pending AS (
    SELECT d.id, d.title, r.user_id
    FROM due d
    JOIN public.event_rsvps r
      ON r.event_id = d.id AND r.status = 'going'
    WHERE d.start_at_utc >  NOW() + INTERVAL '30 minutes'
      AND d.start_at_utc <= NOW() + INTERVAL '60 minutes'
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.user_id = r.user_id
          AND n.type = 'event_reminder_1h'
          AND n.reference_id = d.id::text
      )
  )
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    p.user_id,
    'Starting soon',
    '"' || COALESCE(p.title,'An event you RSVPd to') ||
      '" starts in about an hour.',
    'event_reminder_1h',
    p.id::text,
    'event'
  FROM pending p;
  GET DIAGNOSTICS next_count = ROW_COUNT;
  inserted_count := inserted_count + next_count;

  RETURN inserted_count;
END;
$$;
