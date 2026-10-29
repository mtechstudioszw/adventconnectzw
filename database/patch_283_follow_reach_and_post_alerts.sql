-- ============================================================================
--  patch_283 — follower reach for Home ranking; post alerts from people and
--              Pages you follow, with per-source mute
--  STATUS: APPLIED to the live database 29 Oct 2026 (owner, 29 Oct 2026: "more
--  followers more visibility in home screen only" / "u get notifications
--  from pages or people u follow n option to mute").
-- ============================================================================
--
--  1. author_reach(users, pages) — follower counts for the authors and
--     Pages in a page of the Home feed, so the app can rank bigger
--     accounts a little higher. Used by the Home feed only. Counts are
--     already public (profile_follow_stats / page_stats); this just reads
--     them in one round trip instead of one per author.
--
--  2. follow_alert_mutes — "mute post alerts" for someone or a Page you
--     follow. A separate own-rows-only table rather than a column on
--     `follows`: `follows` rows are readable by BOTH people, so a muted
--     flag there would tell someone you'd muted them.
--
--  3. Post alerts, through a queue (follow_alert_jobs + pg_cron) so a big
--     account's post never fans out inside its own insert — see section 3.
--     notify_followers_of_post() — AFTER INSERT on posts:
--       * Page update → every follower of the Page (minus the author).
--       * Personal post → active followers of the author, PUBLIC posts
--         only: followers see public posts only, so a friends-only post
--         must never ping them.
--     Skips muted followers, and anyone who already got an alert from the
--     same person/Page in the last 2 hours (posting three times in a row
--     is one ping, not three). Each insert also fires the existing push
--     webhook; the daily post limit (trg_post_limit_posts, 3/day) caps the
--     fan-out per author.
--
--  A member can switch all of these off in Settings › Notifications
--  ("Posts from people & Pages you follow" → notif_categories.following);
--  the trigger then creates no row at all, so no push either.
--
--  Fan-out: each alert row still fires the existing push webhook (pg_net,
--  asynchronous). The queue caps it at 5,000 per minute after the first
--  300, and 90-day-inactive followers are skipped.
--
--  Notification types: 'followed_post' (reference_type 'user', reference_id
--  = author) and 'followed_page_post' (reference_type 'page', reference_id
--  = page). Both open screens the app already routes to.
--
--  No profiles columns, no change to shared guards. The new trigger is
--  AFTER INSERT (its return value is ignored) and still returns
--  COALESCE(NEW, OLD) by convention.
-- ============================================================================

BEGIN;

-- 1. Reach ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.author_reach(p_users uuid[], p_pages uuid[])
RETURNS TABLE(id uuid, kind text, followers integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT u.id, 'user'::text,
         (SELECT count(*)::int FROM public.follows f
           WHERE f.followee_id = u.id AND f.status = 'active')
    FROM unnest(COALESCE(p_users, '{}'::uuid[])) AS u(id)
  UNION ALL
  SELECT pg.id, 'page'::text,
         (SELECT count(*)::int FROM public.page_follows pf
           WHERE pf.page_id = pg.id)
    FROM unnest(COALESCE(p_pages, '{}'::uuid[])) AS pg(id);
$function$;

REVOKE ALL ON FUNCTION public.author_reach(uuid[], uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.author_reach(uuid[], uuid[]) TO authenticated;

-- 2. Mutes ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follow_alert_mutes (
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_type text NOT NULL CHECK (target_type IN ('user', 'page')),
  target_id   uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, target_type, target_id)
);

ALTER TABLE public.follow_alert_mutes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS follow_alert_mutes_own_select ON public.follow_alert_mutes;
CREATE POLICY follow_alert_mutes_own_select ON public.follow_alert_mutes
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS follow_alert_mutes_own_insert ON public.follow_alert_mutes;
CREATE POLICY follow_alert_mutes_own_insert ON public.follow_alert_mutes
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS follow_alert_mutes_own_delete ON public.follow_alert_mutes;
CREATE POLICY follow_alert_mutes_own_delete ON public.follow_alert_mutes
  FOR DELETE TO authenticated USING (user_id = auth.uid());

REVOKE ALL ON public.follow_alert_mutes FROM anon;
GRANT SELECT, INSERT, DELETE ON public.follow_alert_mutes TO authenticated;

-- 3. Alerts -----------------------------------------------------------------
-- Built to grow (owner, 29 Oct 2026: "what if the followers increase —
-- prepare for it"). A post never fans out inside the poster's own insert:
--   * the posts trigger only ENQUEUES a job (one small row), then handles
--     the first 300 followers straight away — so a normal account's
--     followers are alerted instantly;
--   * anything left (big accounts) is worked off by pg_cron every minute,
--     5,000 followers per run, resuming from a cursor. ~300,000 alerts an
--     hour, spread out, and posting stays instant however big the account.
-- Followers inactive for 90+ days (profiles.last_active_at) are skipped:
-- they would not see the push, and at scale they are most of the cost.

-- Settings › Notifications › "Posts from people & Pages you follow"
-- (profiles.notif_categories.following). Off = no row and so no push.
-- A missing key means on: every existing member keeps the default.
CREATE OR REPLACE FUNCTION public.wants_follow_alerts(p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT (p.notif_categories ->> 'following') IS DISTINCT FROM 'false'
            AND COALESCE(p.last_active_at, now()) > now() - interval '90 days'
       FROM public.profiles p WHERE p.id = p_user),
    true);
$function$;

REVOKE ALL ON FUNCTION public.wants_follow_alerts(uuid) FROM PUBLIC, anon, authenticated;

-- The queue. Server-only: RLS on with no policies, no grants.
CREATE TABLE IF NOT EXISTS public.follow_alert_jobs (
  id         bigserial PRIMARY KEY,
  post_id    uuid NOT NULL,
  author_id  uuid NOT NULL,
  page_id    uuid,
  title      text NOT NULL,
  body       text NOT NULL,
  cursor     uuid,
  sent       integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  done_at    timestamptz
);
ALTER TABLE public.follow_alert_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.follow_alert_jobs FROM anon, authenticated;
CREATE INDEX IF NOT EXISTS follow_alert_jobs_pending
  ON public.follow_alert_jobs (id) WHERE done_at IS NULL;

-- Work one job for up to p_budget followers. Returns followers examined.
CREATE OR REPLACE FUNCTION public.process_follow_alert_job(p_job bigint, p_budget integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  j public.follow_alert_jobs;
  v_seen integer := 0;
  v_sent integer := 0;
  v_last uuid;
  v_from uuid;
BEGIN
  SELECT * INTO j FROM public.follow_alert_jobs
   WHERE id = p_job AND done_at IS NULL
   FOR UPDATE SKIP LOCKED;
  IF NOT FOUND OR p_budget <= 0 THEN
    RETURN 0;
  END IF;
  v_from := COALESCE(j.cursor, '00000000-0000-0000-0000-000000000000'::uuid);

  IF j.page_id IS NOT NULL THEN
    WITH cand AS (
      SELECT pf.user_id AS rid FROM public.page_follows pf
       WHERE pf.page_id = j.page_id AND pf.user_id > v_from
       ORDER BY pf.user_id LIMIT p_budget
    ), ins AS (
      INSERT INTO public.notifications
        (user_id, title, body, type, reference_id, reference_type)
      SELECT c.rid, j.title, j.body, 'followed_page_post', j.page_id::text, 'page'
        FROM cand c
       WHERE c.rid <> j.author_id
         AND public.wants_follow_alerts(c.rid)
         AND NOT EXISTS (SELECT 1 FROM public.follow_alert_mutes m
                          WHERE m.user_id = c.rid AND m.target_type = 'page'
                            AND m.target_id = j.page_id)
         AND NOT EXISTS (SELECT 1 FROM public.notifications n
                          WHERE n.user_id = c.rid AND n.type = 'followed_page_post'
                            AND n.reference_id = j.page_id::text
                            AND n.created_at > now() - interval '2 hours')
      RETURNING 1
    )
    SELECT (SELECT count(*) FROM cand), (SELECT max(rid::text)::uuid FROM cand),
           (SELECT count(*) FROM ins)
      INTO v_seen, v_last, v_sent;
  ELSE
    WITH cand AS (
      SELECT f.follower_id AS rid FROM public.follows f
       WHERE f.followee_id = j.author_id AND f.status = 'active'
         AND f.follower_id > v_from
       ORDER BY f.follower_id LIMIT p_budget
    ), ins AS (
      INSERT INTO public.notifications
        (user_id, title, body, type, reference_id, reference_type)
      SELECT c.rid, j.title, j.body, 'followed_post', j.author_id::text, 'user'
        FROM cand c
       WHERE public.wants_follow_alerts(c.rid)
         AND NOT EXISTS (SELECT 1 FROM public.follow_alert_mutes m
                          WHERE m.user_id = c.rid AND m.target_type = 'user'
                            AND m.target_id = j.author_id)
         AND NOT EXISTS (SELECT 1 FROM public.notifications n
                          WHERE n.user_id = c.rid AND n.type = 'followed_post'
                            AND n.reference_id = j.author_id::text
                            AND n.created_at > now() - interval '2 hours')
      RETURNING 1
    )
    SELECT (SELECT count(*) FROM cand), (SELECT max(rid::text)::uuid FROM cand),
           (SELECT count(*) FROM ins)
      INTO v_seen, v_last, v_sent;
  END IF;

  UPDATE public.follow_alert_jobs
     SET cursor  = COALESCE(v_last, cursor),
         sent    = sent + v_sent,
         done_at = CASE WHEN v_seen < p_budget THEN now() END
   WHERE id = j.id;
  RETURN v_seen;
END;
$function$;

REVOKE ALL ON FUNCTION public.process_follow_alert_job(bigint, integer) FROM PUBLIC, anon, authenticated;

-- The minute job: oldest first, up to p_budget followers in total.
CREATE OR REPLACE FUNCTION public.process_follow_alert_jobs(p_budget integer DEFAULT 5000)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_left integer := p_budget;
  v_job bigint;
BEGIN
  FOR v_job IN
    SELECT id FROM public.follow_alert_jobs WHERE done_at IS NULL ORDER BY id
  LOOP
    EXIT WHEN v_left <= 0;
    v_left := v_left - public.process_follow_alert_job(v_job, v_left);
  END LOOP;
  DELETE FROM public.follow_alert_jobs
   WHERE done_at < now() - interval '7 days';
  RETURN p_budget - v_left;
END;
$function$;

REVOKE ALL ON FUNCTION public.process_follow_alert_jobs(integer) FROM PUBLIC, anon, authenticated;

-- posts trigger: enqueue, then do the first 300 right away.
CREATE OR REPLACE FUNCTION public.notify_followers_of_post()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_excerpt text;
  v_title text;
  v_job bigint;
BEGIN
  v_excerpt := NULLIF(btrim(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g')), '');
  IF v_excerpt IS NOT NULL AND length(v_excerpt) > 90 THEN
    v_excerpt := left(v_excerpt, 87) || '…';
  END IF;

  IF NEW.page_id IS NOT NULL THEN
    SELECT name INTO v_title FROM public.pages
     WHERE id = NEW.page_id AND status = 'active';
    IF v_title IS NULL THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
    INSERT INTO public.follow_alert_jobs (post_id, author_id, page_id, title, body)
    VALUES (NEW.id, NEW.author_id, NEW.page_id, v_title,
            COALESCE(v_excerpt, 'Shared a new update.'))
    RETURNING id INTO v_job;
  ELSE
    -- Personal post: followers see public posts only.
    IF COALESCE(NEW.visibility, 'public') <> 'public' THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
    INSERT INTO public.follow_alert_jobs (post_id, author_id, title, body)
    VALUES (NEW.id, NEW.author_id, public.notif_actor_name(NEW.author_id),
            COALESCE('Posted: ' || v_excerpt, 'Shared a new post.'))
    RETURNING id INTO v_job;
  END IF;

  PERFORM public.process_follow_alert_job(v_job, 300);
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS posts_notify_followers ON public.posts;
CREATE TRIGGER posts_notify_followers AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_followers_of_post();

-- Throttle lookup: one index on what the NOT EXISTS above filters by.
CREATE INDEX IF NOT EXISTS notifications_follow_alert_throttle
  ON public.notifications (user_id, type, reference_id, created_at)
  WHERE type IN ('followed_post', 'followed_page_post');

-- Every minute, work off whatever big accounts left in the queue.
SELECT cron.unschedule('follow-alert-fanout')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'follow-alert-fanout');
SELECT cron.schedule('follow-alert-fanout', '* * * * *',
  $cron$SELECT public.process_follow_alert_jobs(5000)$cron$);

NOTIFY pgrst, 'reload schema';

COMMIT;
