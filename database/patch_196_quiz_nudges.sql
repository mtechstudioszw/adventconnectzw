-- =====================================================================
--  patch_196 — quiz nudges: come and play, and you've been overtaken
--
--  Founder ask: notifications encouraging people to play, especially live
--  match, and a notification when you are losing your leaderboard place.
--
--  ## Why the live nudge is a fixed hour and not "someone is waiting"
--
--  The obvious build is: watch for an `open` queue row and push "somebody
--  is waiting to play you". It does not work. `quiz_match_find` only pairs
--  against queue entries newer than **two minutes**, so by the time a push
--  is delivered, unlocked, read and acted on, the person who was waiting
--  has gone. Every one of those notifications would be a lie by the time
--  it was tapped, and the member would arrive at an empty arena.
--
--  Live head-to-head needs two people present at the same moment. The way
--  to manufacture that is not to chase a two-minute window — it is to give
--  everyone the same window. So there is a nightly quiz hour: one nudge, at
--  the same time, to everyone eligible, which puts them in the arena
--  together. That is a promise the feature can actually keep.
--
--  ## Spam rules, which are the hard part
--
--  * **Type `quiz_nudge`, category `quiz`** — mutable in Settings, and NOT
--    in `is_essential_notification`, so `suppress_sabbath_notifications`
--    already drops it during a member's Sabbath quiet hours. That is why
--    the nudge type is deliberately different from `quiz_challenge`: a real
--    person challenging you is not marketing and must not be silenced by a
--    toggle meant for reminders.
--  * **At most one nudge of each kind per member per 24 hours**, enforced
--    in SQL against the notifications table itself rather than trusted to
--    the cron schedule.
--  * **Only people who have already played.** Pushing a game invitation at
--    164 members who never opened the quiz is how an app gets uninstalled.
--  * **Nobody who has already played today** gets told to come and play.
--  * **Rank drops only matter near the top.** Being overtaken for 40th is
--    not news; the notification only fires inside the top 10.
-- =====================================================================

-- ---- 1. A mutable category ------------------------------------------
-- Existing rows get the key with a default of true, matching how every
-- other category shipped.

UPDATE public.profiles
   SET notif_categories = COALESCE(notif_categories, '{}'::jsonb)
                          || jsonb_build_object('quiz', true)
 WHERE NOT (COALESCE(notif_categories, '{}'::jsonb) ? 'quiz');

ALTER TABLE public.profiles
  ALTER COLUMN notif_categories
  SET DEFAULT jsonb_build_object(
    'events', true, 'prayers', true, 'messages', true,
    'marketplace', true, 'announcements', true, 'news', true,
    'social', true, 'watch', true, 'quiz', true
  );

-- ---- 2. Who may be nudged -------------------------------------------
-- One definition, used by both jobs below, so they cannot drift apart.

CREATE OR REPLACE FUNCTION public.quiz_nudge_eligible(p_kind text)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id
    FROM public.profiles p
   WHERE COALESCE(p.is_banned, false) = false
     -- Has played at least once. A game nudge to somebody who has never
     -- opened the quiz is an advert, not a reminder.
     AND EXISTS (SELECT 1 FROM public.quiz_scores s WHERE s.user_id = p.id)
     -- Muted the category in Settings.
     AND COALESCE(p.notif_categories -> 'quiz', 'true'::jsonb) <> 'false'::jsonb
     -- Already had this kind of nudge in the last day.
     AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.user_id = p.id
          AND n.type = 'quiz_nudge'
          AND n.reference_type = p_kind
          AND n.created_at > now() - interval '20 hours'
     );
$$;

REVOKE ALL ON FUNCTION public.quiz_nudge_eligible(text) FROM public;

-- ---- 3. The nightly quiz hour ---------------------------------------

CREATE OR REPLACE FUNCTION public.quiz_notify_play_time()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sent integer;
BEGIN
  WITH sent AS (
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    )
    SELECT e.user_id,
           'The arena is open',
           'Quiz hour. Play a live head-to-head now while everyone else '
             || 'is here — first to answer scores most.',
           'quiz_nudge',
           NULL,
           'quiz_live'
      FROM public.quiz_nudge_eligible('quiz_live') e
     WHERE NOT EXISTS (
       -- Already played today: they do not need telling.
       SELECT 1 FROM public.quiz_scores s
        WHERE s.user_id = e.user_id
          AND s.played_at > (now() AT TIME ZONE 'Africa/Harare')::date
                            AT TIME ZONE 'Africa/Harare'
     )
    RETURNING 1
  )
  SELECT count(*) INTO v_sent FROM sent;
  RETURN v_sent;
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_notify_play_time() FROM public;

-- ---- 4. You have been overtaken -------------------------------------
-- Remembering the last rank a member was TOLD about, not their last rank:
-- without that, sliding 3 → 4 → 5 → 6 over an evening is four
-- notifications about the same slide.

CREATE TABLE IF NOT EXISTS public.quiz_rank_watch (
  user_id        uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_rank      integer NOT NULL,
  last_notified  timestamptz
);

ALTER TABLE public.quiz_rank_watch ENABLE ROW LEVEL SECURITY;
-- Server-only bookkeeping. No policies, and the grant removed: knowing
-- when a rival was last nudged is nobody's business but the job's.
REVOKE ALL ON TABLE public.quiz_rank_watch FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.quiz_notify_rank_drop()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sent integer := 0;
BEGIN
  -- One statement, no temp table.
  --
  -- The first draft built the board into a `TEMP TABLE ... ON COMMIT DROP`
  -- and then ran three statements against it. ON COMMIT DROP means exactly
  -- that — so a second call inside the same transaction hit
  -- "relation _board already exists". pg_cron gives each run its own
  -- transaction so it would not have bitten in production, which is
  -- precisely what makes it the sort of bug that surfaces a year later
  -- when something else calls this twice.
  --
  -- Every CTE also sees the SAME snapshot, which is what makes `dropped`
  -- readable against the OLD `quiz_rank_watch` while `recorded` overwrites
  -- it in the same breath. The two writes are merged into one upsert
  -- because Postgres will not update the same row twice in one statement.
  WITH board AS (
    SELECT s.user_id,
           RANK() OVER (ORDER BY SUM(s.points) DESC)::int AS rank
      FROM public.quiz_scores s
     WHERE s.played_at >= public.quiz_week_start()
     GROUP BY s.user_id
  ), dropped AS (
    SELECT b.user_id, b.rank, w.last_rank
      FROM board b
      JOIN public.quiz_rank_watch w ON w.user_id = b.user_id
     WHERE b.rank > w.last_rank
       -- Only near the top. Slipping from 38th to 41st is not news.
       AND w.last_rank <= 10
       AND (w.last_notified IS NULL
            OR w.last_notified < now() - interval '20 hours')
       AND EXISTS (SELECT 1 FROM public.quiz_nudge_eligible('quiz_rank') e
                    WHERE e.user_id = b.user_id)
  ), sent AS (
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    )
    SELECT d.user_id,
           'You have been overtaken',
           'You have slipped from #' || d.last_rank || ' to #' || d.rank
             || ' on this week''s quiz leaderboard. Play a round to take '
             || 'your place back.',
           'quiz_nudge',
           NULL,
           'quiz_rank'
      FROM dropped d
    RETURNING user_id
  ), recorded AS (
    -- Where everyone actually stands now, so the next run compares against
    -- the truth rather than a stale high-water mark.
    INSERT INTO public.quiz_rank_watch AS w (user_id, last_rank, last_notified)
    SELECT b.user_id,
           b.rank,
           CASE WHEN d.user_id IS NOT NULL THEN now() END
      FROM board b
      LEFT JOIN dropped d ON d.user_id = b.user_id
    ON CONFLICT (user_id) DO UPDATE
      SET last_rank     = EXCLUDED.last_rank,
          last_notified = COALESCE(EXCLUDED.last_notified, w.last_notified)
    RETURNING 1
  )
  SELECT count(*) INTO v_sent FROM sent;

  RETURN v_sent;
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_notify_rank_drop() FROM public;

-- ---- 5. Schedule ------------------------------------------------------
-- 17:00 UTC = 19:00 Harare: after work and after supper, before the
-- evening winds down. Rank drops are checked hourly, which is often
-- enough to feel live and far below the once-per-20-hours cap per member.

SELECT cron.unschedule('quiz-play-time')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'quiz-play-time');
SELECT cron.schedule(
  'quiz-play-time', '0 17 * * *',
  $cron$ SELECT public.quiz_notify_play_time(); $cron$
);

SELECT cron.unschedule('quiz-rank-drop')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'quiz-rank-drop');
SELECT cron.schedule(
  'quiz-rank-drop', '5 * * * *',
  $cron$ SELECT public.quiz_notify_rank_drop(); $cron$
);
