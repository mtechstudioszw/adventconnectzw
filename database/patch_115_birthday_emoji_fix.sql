-- =====================================================================
--  PATCH 115 — birthday notifications: fix the corrupted cake emoji.
--
--  The 🎂 in notify_birthdays() got mangled into two ASCII '?' chars when
--  the function was first applied (the literal travelled through a non-UTF8
--  step). Friends literally saw "It's Michael's birthday ??".
--
--  Fix: build the emoji with chr(127874) (U+1F382) so the SQL itself stays
--  pure ASCII and can never corrupt in transit again. Also repair the rows
--  that were already inserted today.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_birthdays()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  bday RECORD;
  friend_id UUID;
BEGIN
  FOR bday IN
    SELECT id, COALESCE(NULLIF(TRIM(full_name), ''), 'A member') AS name
    FROM public.profiles
    WHERE date_of_birth IS NOT NULL
      AND is_banned = FALSE
      AND EXTRACT(MONTH FROM date_of_birth) =
          EXTRACT(MONTH FROM (now() AT TIME ZONE 'Africa/Harare'))
      AND EXTRACT(DAY FROM date_of_birth) =
          EXTRACT(DAY FROM (now() AT TIME ZONE 'Africa/Harare'))
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.notifications
      WHERE type = 'birthday'
        AND reference_id = bday.id::text
        AND created_at > now() - interval '20 hours'
    ) THEN
      CONTINUE;
    END IF;

    -- The birthday person.
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    VALUES (bday.id, 'Happy Birthday! ' || chr(127874),
            'Wishing you a blessed birthday from everyone at Advent Connect ZW.',
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
$function$;

-- Repair rows already inserted with the mangled '??' suffix.
UPDATE public.notifications
SET title = regexp_replace(title, '\?\?$', chr(127874))
WHERE type = 'birthday'
  AND title LIKE '%??';
