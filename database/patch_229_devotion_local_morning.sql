-- =====================================================================
--  PATCH 229 — The devotion appears hours before its notification, and
--               everyone outside Zimbabwe is notified at the wrong time
--
--  Reported 23 Aug 2026: "the devotion card updates before the
--  notification is fired ... also how does it cope with other countries
--  besides Zimbabwe, it should give them these notifications based on
--  their morning too".
--
--  Both symptoms are the same root cause: the devotion's DAY and the
--  devotion's NOTIFICATION were each pinned to a different fixed clock,
--  and neither of them was the member's.
--
--  ## Bug 1 — the card flips 7 hours early
--
--  `todays_devotion()` picked its row with
--
--      EXTRACT(doy FROM (now() AT TIME ZONE 'Africa/Harare'))
--
--  so the devotion advanced at MIDNIGHT in Harare — 22:00 UTC. The
--  notification cron ran at `0 5 * * *` (05:00 UTC = 07:00 in Harare).
--  Between those two moments, seven hours long, the app was already
--  showing tomorrow's devotion to someone who had not been told about it
--  yet. Opening the app at 6am showed the "new" devotion; the push then
--  arrived at 7am announcing something already read.
--
--  ## Bug 2 — one fixed UTC hour for the whole world
--
--  `0 5 * * *` is 07:00 only in Zimbabwe. The same job reached a member in
--  London at 06:00, New York at 01:00, and Sydney at 15:00. There are
--  members in 11 countries in this database, spanning most of the globe.
--
--  ## The fix
--
--  One rule, applied in both places: **the devotional day turns over at
--  07:00 in the MEMBER'S OWN timezone.** The card and the push then agree
--  by construction, in every country, instead of by coincidence in one.
--
--  1. `country_timezones` maps ISO-3166 alpha-2 → a representative IANA
--     zone. Representative is the right granularity here: this decides
--     which morning to greet someone in, not when to fire a rocket, and
--     `profiles.country` is all the location the app collects.
--
--  2. `todays_devotion()` resolves the CALLER's country itself, so the
--     Flutter client needs no change and keeps calling it with no
--     arguments. Falls back to Africa/Harare — the previous behaviour and
--     the right default for 221 of 235 members.
--
--  3. `enqueue_daily_devotion()` becomes hourly and sends only to members
--     whose local time is currently 07:00, with a 20-hour dedupe so a
--     retry or a DST shift cannot double-send.
-- =====================================================================

-- ---- 1. country → timezone ------------------------------------------
CREATE TABLE IF NOT EXISTS public.country_timezones (
  country_code text PRIMARY KEY,
  tz           text NOT NULL
);

ALTER TABLE public.country_timezones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS country_timezones_read ON public.country_timezones;
CREATE POLICY country_timezones_read ON public.country_timezones
  FOR SELECT USING (auth.role() = 'authenticated');

-- Seeded well beyond the 11 countries currently present: a new member
-- signing up from an unlisted country would silently fall back to
-- Harare's morning, and the point of this patch is that they should not.
INSERT INTO public.country_timezones (country_code, tz) VALUES
  ('ZW','Africa/Harare'),      ('ZA','Africa/Johannesburg'),
  ('KE','Africa/Nairobi'),     ('GH','Africa/Accra'),
  ('AO','Africa/Luanda'),      ('NG','Africa/Lagos'),
  ('TZ','Africa/Dar_es_Salaam'),('UG','Africa/Kampala'),
  ('ZM','Africa/Lusaka'),      ('MW','Africa/Blantyre'),
  ('MZ','Africa/Maputo'),      ('BW','Africa/Gaborone'),
  ('NA','Africa/Windhoek'),    ('ET','Africa/Addis_Ababa'),
  ('RW','Africa/Kigali'),      ('EG','Africa/Cairo'),
  ('GB','Europe/London'),      ('IE','Europe/Dublin'),
  ('DE','Europe/Berlin'),      ('FR','Europe/Paris'),
  ('NL','Europe/Amsterdam'),   ('ES','Europe/Madrid'),
  ('IT','Europe/Rome'),        ('PT','Europe/Lisbon'),
  ('SE','Europe/Stockholm'),   ('NO','Europe/Oslo'),
  ('RU','Europe/Moscow'),      ('UA','Europe/Kyiv'),
  ('US','America/New_York'),   ('CA','America/Toronto'),
  ('BR','America/Sao_Paulo'),  ('JM','America/Jamaica'),
  ('TT','America/Port_of_Spain'),('MX','America/Mexico_City'),
  ('AU','Australia/Sydney'),   ('NZ','Pacific/Auckland'),
  ('VU','Pacific/Efate'),      ('FJ','Pacific/Fiji'),
  ('PG','Pacific/Port_Moresby'),
  ('IN','Asia/Kolkata'),       ('PK','Asia/Karachi'),
  ('PH','Asia/Manila'),        ('ID','Asia/Jakarta'),
  ('CN','Asia/Shanghai'),      ('JP','Asia/Tokyo'),
  ('KR','Asia/Seoul'),         ('AE','Asia/Dubai'),
  ('SA','Asia/Riyadh'),        ('IL','Asia/Jerusalem')
ON CONFLICT (country_code) DO UPDATE SET tz = EXCLUDED.tz;

-- Resolve a country code to a zone, defaulting to Harare.
CREATE OR REPLACE FUNCTION public.tz_for_country(p_country text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT tz FROM public.country_timezones
      WHERE country_code = upper(NULLIF(btrim(p_country), ''))),
    'Africa/Harare'
  );
$function$;

-- ---- 2. the devotional day, per member -------------------------------
--
-- The `- interval '7 hours'` is the whole trick: shifting local time back
-- by the delivery hour before taking the day-of-year means the index only
-- advances once local time reaches 07:00. At 06:59 it still resolves to
-- yesterday's devotion; at 07:00, the moment the push goes out, it
-- becomes today's. Card and notification cannot drift apart, because they
-- are now computed from the same expression.
CREATE OR REPLACE FUNCTION public.devotion_day_index(p_tz text)
RETURNS int
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT EXTRACT(
           doy FROM ((now() AT TIME ZONE p_tz) - interval '7 hours')
         )::int
       % GREATEST((SELECT count(*)::int FROM public.daily_devotions), 1);
$function$;

CREATE OR REPLACE FUNCTION public.todays_devotion()
RETURNS daily_devotions
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT * FROM public.daily_devotions
   ORDER BY id
   OFFSET public.devotion_day_index(
            public.tz_for_country(
              (SELECT country FROM public.profiles WHERE id = auth.uid())
            )
          )
   LIMIT 1;
$function$;

-- ---- 3. notify each country in its own morning -----------------------
CREATE OR REPLACE FUNCTION public.enqueue_daily_devotion()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- One statement, per-member: each row picks the devotion for ITS OWN
  -- timezone, so a single hourly pass serves every country correctly
  -- rather than one country correctly and the rest at random hours.
  INSERT INTO public.notifications (user_id, title, body, type, reference_type)
  SELECT p.id,
         'Today''s Devotion 🙏',
         d.bible_ref || ' — ' || d.bible_text,
         'devotion', 'devotion'
    FROM public.profiles p
    CROSS JOIN LATERAL (
      SELECT public.tz_for_country(p.country) AS tz
    ) z
    CROSS JOIN LATERAL (
      SELECT * FROM public.daily_devotions
       ORDER BY id
       OFFSET public.devotion_day_index(z.tz)
       LIMIT 1
    ) d
   -- Only members for whom it is currently the 07:00 hour, locally.
   WHERE EXTRACT(hour FROM (now() AT TIME ZONE z.tz))::int = 7
     -- Dedupe. The job now runs 24x a day instead of once, so "have we
     -- already sent today's?" has to be asked explicitly — a retry, a
     -- clock adjustment or a DST transition must not double-send.
     AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.user_id = p.id
          AND n.type = 'devotion'
          AND n.created_at > now() - interval '20 hours'
     );
END;
$function$;

-- ---- 4. hourly, not 05:00 UTC ----------------------------------------
-- The function now decides WHO to send to; the schedule only has to give
-- it the chance to look, once per hour. Minute 0 keeps delivery on the
-- hour in every zone, including the 30- and 45-minute offset ones
-- (Asia/Kolkata, Pacific/Chatham) — they simply receive within the hour.
SELECT cron.schedule(
  'daily-devotion',
  '0 * * * *',
  $$SELECT public.enqueue_daily_devotion();$$
);

-- ---------------------------------------------------------------------
--  NOT FIXED HERE, AND IT IS THE BIGGER PROBLEM: there are only 12 rows
--  in daily_devotions. `devotion_day_index` is `doy % 12`, so the app
--  cycles the same twelve devotions every twelve days — roughly 30 times
--  a year, always in id order. That is the "the devotions feel like a
--  pattern and keep repeating" report, and no scheduling change touches
--  it. It needs content: at minimum 366 rows for a non-repeating year.
-- ---------------------------------------------------------------------
