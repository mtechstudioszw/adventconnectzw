-- =====================================================================
--  PATCH 108 — Daily Devotions (Bible verse + Ellen G. White quote)
--
--  Content is strictly PUBLIC DOMAIN: KJV Bible text + Ellen G. White
--  writings (she died in 1915, so her works are public domain). A daily
--  pg_cron job pushes the day's devotion to every user (notify-fcm fans
--  it out), and the Home card shows todays_devotion().
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.daily_devotions (
  id          BIGSERIAL PRIMARY KEY,
  bible_ref   TEXT NOT NULL,
  bible_text  TEXT NOT NULL,
  egw_quote   TEXT NOT NULL,
  egw_source  TEXT NOT NULL,
  theme       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.daily_devotions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS daily_devotions_read ON public.daily_devotions;
CREATE POLICY daily_devotions_read ON public.daily_devotions
  FOR SELECT TO anon, authenticated USING (true);

INSERT INTO public.daily_devotions (bible_ref, bible_text, egw_quote, egw_source, theme) VALUES
('Luke 21:28', 'And when these things begin to come to pass, then look up, and lift up your heads; for your redemption draweth nigh.', 'We have nothing to fear for the future, except as we shall forget the way the Lord has led us, and His teaching in our past history.', 'Life Sketches, p. 196', 'last days'),
('Titus 2:13', 'Looking for that blessed hope, and the glorious appearing of the great God and our Saviour Jesus Christ.', 'Soon we shall see Him in whom our hopes of eternal life are centered.', 'The Great Controversy', 'second coming'),
('Matthew 24:42', 'Watch therefore: for ye know not what hour your Lord doth come.', 'Our work is to be in readiness for the events that are coming upon us as a thief in the night.', 'Testimonies, vol. 8', 'watchfulness'),
('Revelation 22:12', 'And, behold, I come quickly; and my reward is with me, to give every man according as his work shall be.', 'Heaven is worth everything to us, and if we lose heaven we lose all.', 'Testimonies, vol. 2', 'reward'),
('2 Peter 3:9', 'The Lord is not slack concerning his promise... but is longsuffering to us-ward, not willing that any should perish.', 'God''s love for His children during the period of their severest trial is as strong and tender as in the days of their sunniest prosperity.', 'The Desire of Ages', 'patience'),
('Isaiah 41:10', 'Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee.', 'When trials beset us, let us remember that the Lord is on the throne, and that He overrules all things for the good of His people.', 'Selected Messages', 'courage'),
('Psalm 46:1', 'God is our refuge and strength, a very present help in trouble.', 'There is no danger that the Lord will neglect the prayers of His people.', 'The Great Controversy', 'refuge'),
('Matthew 24:14', 'And this gospel of the kingdom shall be preached in all the world for a witness... and then shall the end come.', 'The Saviour''s commission to the disciples included all the believers... to the end of time.', 'The Acts of the Apostles', 'mission'),
('Philippians 4:6', 'Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.', 'Prayer is the breath of the soul. It is the secret of spiritual power.', 'Gospel Workers', 'prayer'),
('John 14:1', 'Let not your heart be troubled: ye believe in God, believe also in me.', 'Christ alone is able to help us and to give us the victory.', 'The Ministry of Healing', 'comfort'),
('Revelation 14:12', 'Here is the patience of the saints: here are they that keep the commandments of God, and the faith of Jesus.', 'The last message of mercy to be given to the world is a revelation of His character of love.', 'Christ''s Object Lessons', 'endurance'),
('Lamentations 3:22', 'It is of the LORD''s mercies that we are not consumed, because his compassions fail not. They are new every morning.', 'Each morning consecrate yourself to God for that day.', 'Steps to Christ', 'mercy');

-- The day's devotion — rotates through the table by day of year.
CREATE OR REPLACE FUNCTION public.todays_devotion()
RETURNS public.daily_devotions LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT * FROM public.daily_devotions
   ORDER BY id
   OFFSET (EXTRACT(doy FROM (now() AT TIME ZONE 'Africa/Harare'))::int %
           GREATEST((SELECT count(*)::int FROM public.daily_devotions), 1))
   LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.todays_devotion() TO anon, authenticated;

-- Daily push: one notification row per user (notify-fcm pushes each).
CREATE OR REPLACE FUNCTION public.enqueue_daily_devotion()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d public.daily_devotions;
BEGIN
  SELECT * INTO d FROM public.todays_devotion();
  IF d.id IS NULL THEN RETURN; END IF;
  INSERT INTO public.notifications (user_id, title, body, type, reference_type)
  SELECT p.id,
         'Today''s Devotion 🙏',
         d.bible_ref || ' — ' || d.bible_text,
         'devotion', 'devotion'
    FROM public.profiles p;
END;
$$;

-- 05:00 UTC = 07:00 Harare — a morning devotion.
SELECT cron.schedule('daily-devotion', '0 5 * * *',
  'SELECT public.enqueue_daily_devotion();');
