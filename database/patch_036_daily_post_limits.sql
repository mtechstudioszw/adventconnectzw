-- =====================================================================
--  PATCH 036 — Daily per-user post limits (3-per-24h, server-enforced)
--
--  WHY: Founder direction (2026-06-01): cap how often a single user
--       can publish on each post-style surface so a spammer (or a
--       compromised account, or someone hammering the bypass-the-app
--       Supabase REST endpoints directly) can't flood the marketplace,
--       prayer feed, advent news, jobs, stories, home posts, or
--       events. Client-side guards would be bypassable by anyone with
--       a PostgREST URL; the only durable answer is a SECURITY DEFINER
--       trigger that consumes a slot in the rate_limits table
--       (patch_026) and refuses the INSERT once 3 hits in 24 h are
--       used up. The same RPC powers the password-reset throttle, so
--       this just layers a new action key per table.
--
--  WHAT:
--   1. enforce_daily_post_limit() — generic BEFORE INSERT trigger fn.
--      Reads the row's author/seller/poster column based on the
--      triggered table, fans out to check_and_consume_rate_limit
--      with action=TG_ARGV[0] and max=TG_ARGV[1] (default 3). Skips
--      itself when auth.uid() IS NULL (server-role admin maintenance)
--      and when the caller is is_super_admin = TRUE (so super-admin
--      curation isn't gated). Raises a friendly exception with
--      SQLSTATE P0001 and a HINT containing the action key so the
--      Flutter side can detect "post limit" errors specifically and
--      surface a 24-hour cooldown copy.
--   2. Triggers attached to: products, prayers, advent_news, jobs,
--      stories, posts, events. Each uses its own action_key so users
--      can post 3 prayers AND 3 products in the same day without one
--      eating the other's budget.
--
--  PREREQUISITES: patch_026 (rate_limits + check_and_consume_rate_limit)
--                 patch_023 (profiles.is_super_admin)
--  IDEMPOTENT:    yes — CREATE OR REPLACE + DROP TRIGGER IF EXISTS.
-- =====================================================================


CREATE OR REPLACE FUNCTION public.enforce_daily_post_limit()
RETURNS TRIGGER AS $$
DECLARE
  v_action  TEXT    := TG_ARGV[0];
  v_max     INTEGER := COALESCE(NULLIF(TG_ARGV[1], '')::INT, 3);
  v_caller  UUID    := auth.uid();
  v_user    UUID;
  v_admin   BOOLEAN;
  v_ok      BOOLEAN;
BEGIN
  -- Server-role maintenance (Supabase Studio queries, migrations,
  -- nightly jobs) runs with auth.uid() = NULL — never throttle that.
  IF v_caller IS NULL THEN
    RETURN NEW;
  END IF;

  -- Super admins curate the feed and approve content — they shouldn't
  -- hit the 3-per-day cap. Fail-soft if the profile row is missing.
  SELECT COALESCE(is_super_admin, FALSE)
    INTO v_admin
    FROM public.profiles
   WHERE id = v_caller;
  IF v_admin THEN
    RETURN NEW;
  END IF;

  -- Pick the column on NEW that identifies the post author. New
  -- post-style tables added later just need a CASE branch here.
  CASE TG_TABLE_NAME
    WHEN 'products'    THEN v_user := NEW.seller_id;
    WHEN 'prayers'     THEN v_user := NEW.author_id;
    WHEN 'advent_news' THEN v_user := NEW.author_id;
    WHEN 'jobs'        THEN v_user := NEW.poster_id;
    WHEN 'stories'     THEN v_user := NEW.author_id;
    WHEN 'posts'       THEN v_user := NEW.author_id;
    WHEN 'events'      THEN v_user := NEW.organizer_id;
    ELSE                    v_user := NULL;
  END CASE;

  -- If we can't identify the author (table schema drift), fail open
  -- rather than block real users. The trigger is a safety net, not
  -- the primary auth check.
  IF v_user IS NULL THEN
    RETURN NEW;
  END IF;

  -- The rate_limits row is keyed on the user, so spammers can't
  -- get extra slots by passing a fake seller_id — the RLS on each
  -- table already requires the seller/author column to match
  -- auth.uid() via patch policies.

  v_ok := public.check_and_consume_rate_limit(
    v_user::text,
    v_action,
    v_max,
    86400  -- 24 hours
  );

  IF NOT v_ok THEN
    -- HINT carries the action key so the Flutter side can match
    -- against POST_LIMIT_HINTS and show the right "3/3 used, try
    -- again in 24h" copy. SQLSTATE P0001 is the standard
    -- raise_exception code; using it lets us avoid clashing with
    -- table-specific constraint codes.
    RAISE EXCEPTION
      'Daily post limit reached for this section. '
      'You can post again in 24 hours.'
      USING HINT = v_action;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;


-- ----- 2. Attach triggers (one per post-style table) ----------------

DROP TRIGGER IF EXISTS trg_post_limit_products    ON public.products;
CREATE TRIGGER trg_post_limit_products
  BEFORE INSERT ON public.products
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_product', '3');

DROP TRIGGER IF EXISTS trg_post_limit_prayers     ON public.prayers;
CREATE TRIGGER trg_post_limit_prayers
  BEFORE INSERT ON public.prayers
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_prayer', '3');

DROP TRIGGER IF EXISTS trg_post_limit_advent_news ON public.advent_news;
CREATE TRIGGER trg_post_limit_advent_news
  BEFORE INSERT ON public.advent_news
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_advent_news', '3');

DROP TRIGGER IF EXISTS trg_post_limit_jobs        ON public.jobs;
CREATE TRIGGER trg_post_limit_jobs
  BEFORE INSERT ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_job', '3');

DROP TRIGGER IF EXISTS trg_post_limit_stories     ON public.stories;
CREATE TRIGGER trg_post_limit_stories
  BEFORE INSERT ON public.stories
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_story', '3');

DROP TRIGGER IF EXISTS trg_post_limit_posts       ON public.posts;
CREATE TRIGGER trg_post_limit_posts
  BEFORE INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_feed', '3');

DROP TRIGGER IF EXISTS trg_post_limit_events      ON public.events;
CREATE TRIGGER trg_post_limit_events
  BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION
    public.enforce_daily_post_limit('post_event', '3');
