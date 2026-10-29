-- =====================================================================
--  PATCH 291 — stop the Watch/Home video query timing out
--  STATUS: not yet applied
--
--  Found 29 Oct 2026 in the logs: 231 "500" errors in 24 h on
--    youtube_videos?live_status=neq.upcoming&order=published_at.desc.nullslast
--  and 330 "canceling statement due to statement timeout" in Postgres.
--
--  Cause: the app orders by `published_at DESC NULLS LAST`, but the only
--  index is `published_at DESC` — which in Postgres means NULLS FIRST. The
--  orders don't match, so the planner can't use it: every request
--  sequentially scanned and sorted all ~71,600 videos (and ran the RLS
--  channel check on each) just to return the newest 3. Under load that
--  passes the statement timeout, and the slow queries crowd the database
--  so unrelated calls (profiles, maintenance_status) time out too.
--
--  Fix: an index in exactly the order the app asks for. Built
--  CONCURRENTLY so the table stays readable while it builds.
--
--  RUN THIS AS IT IS, ON ITS OWN: CREATE INDEX CONCURRENTLY cannot run
--  inside a transaction, so there is deliberately no BEGIN/COMMIT here.
--  It takes well under a minute on this table.
--
--  No profiles change, no triggers — the CLAUDE.md checklist doesn't
--  arise.
-- =====================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_yt_videos_published_nulls_last
  ON public.youtube_videos (published_at DESC NULLS LAST);

ANALYZE public.youtube_videos;

-- ---------------------------------------------------------------------
--  Check it worked (read-only). Expect the plan to say
--  "Index Scan using idx_yt_videos_published_nulls_last" — not "Seq Scan".
-- ---------------------------------------------------------------------
-- EXPLAIN SELECT * FROM public.youtube_videos
--  WHERE live_status <> 'upcoming'
--  ORDER BY published_at DESC NULLS LAST LIMIT 3;
