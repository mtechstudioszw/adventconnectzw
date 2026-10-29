-- ============================================================================
--  patch_283 — follower reach for Home ranking; post alerts from people and
--              Pages you follow, with per-source mute
--  STATUS: DRAFT — rehearse, then apply (owner, 29 Oct 2026: "more
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
--  3. notify_followers_of_post() — AFTER INSERT on posts:
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
CREATE OR REPLACE FUNCTION public.notify_followers_of_post()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_excerpt text;
  v_page_name text;
BEGIN
  v_excerpt := NULLIF(btrim(regexp_replace(COALESCE(NEW.body, ''), '\s+', ' ', 'g')), '');
  IF v_excerpt IS NOT NULL AND length(v_excerpt) > 90 THEN
    v_excerpt := left(v_excerpt, 87) || '…';
  END IF;

  IF NEW.page_id IS NOT NULL THEN
    SELECT name INTO v_page_name FROM public.pages
     WHERE id = NEW.page_id AND status = 'active';
    IF v_page_name IS NULL THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    SELECT pf.user_id,
           v_page_name,
           COALESCE(v_excerpt, 'Shared a new update.'),
           'followed_page_post',
           NEW.page_id::text,
           'page'
      FROM public.page_follows pf
     WHERE pf.page_id = NEW.page_id
       AND pf.user_id <> NEW.author_id
       AND NOT EXISTS (SELECT 1 FROM public.follow_alert_mutes m
                        WHERE m.user_id = pf.user_id
                          AND m.target_type = 'page'
                          AND m.target_id = NEW.page_id)
       AND NOT EXISTS (SELECT 1 FROM public.notifications n
                        WHERE n.user_id = pf.user_id
                          AND n.type = 'followed_page_post'
                          AND n.reference_id = NEW.page_id::text
                          AND n.created_at > now() - interval '2 hours');
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Personal post: followers see public posts only.
  IF COALESCE(NEW.visibility, 'public') <> 'public' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  SELECT f.follower_id,
         public.notif_actor_name(NEW.author_id),
         COALESCE('Posted: ' || v_excerpt, 'Shared a new post.'),
         'followed_post',
         NEW.author_id::text,
         'user'
    FROM public.follows f
   WHERE f.followee_id = NEW.author_id
     AND f.status = 'active'
     AND NOT EXISTS (SELECT 1 FROM public.follow_alert_mutes m
                      WHERE m.user_id = f.follower_id
                        AND m.target_type = 'user'
                        AND m.target_id = NEW.author_id)
     AND NOT EXISTS (SELECT 1 FROM public.notifications n
                      WHERE n.user_id = f.follower_id
                        AND n.type = 'followed_post'
                        AND n.reference_id = NEW.author_id::text
                        AND n.created_at > now() - interval '2 hours');
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

NOTIFY pgrst, 'reload schema';

COMMIT;
