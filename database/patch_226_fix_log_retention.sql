-- =====================================================================
--  PATCH 226 — patch_190's retention job has never once succeeded
--
--  Measured 23 Aug 2026. Database back to 412 MB of a 500 MB plan, with
--  the same two tables patch_190 was written to control:
--
--    net._http_response      111 MB  — for 690 live rows
--    cron.job_run_details     28 MB  — 32,404 rows back to 9 Aug
--    supabase_functions.hooks 21 MB  — 147,493 rows back to 18 May
--
--  patch_190 scheduled `prune-operational-logs` nightly at 03:50 to keep
--  the first two small. cron.job_run_details records what actually
--  happened, every night since it was installed:
--
--    status:  failed
--    ERROR:   VACUUM cannot be executed from a function
--    CONTEXT: SQL statement "VACUUM FULL net._http_response"
--             PL/pgSQL function prune_operational_logs() line 9 at EXECUTE
--
--  VACUUM cannot run inside a transaction block, and a PL/pgSQL function
--  body is ALWAYS one. `EXECUTE 'VACUUM FULL ...'` inside a function is
--  not "usually fine" — it is unconditionally an error, so this line
--  could never have worked on any database, and the failure was silent
--  because nobody reads cron.job_run_details.
--
--  ## The part that made it worse than "the vacuum didn't happen"
--
--  The raise aborts the function at line 9, so the statement AFTER it —
--  the one pruning cron.job_run_details — never ran either. A patch that
--  covered two tables therefore delivered NEITHER, and the second one
--  failed for a reason that has nothing to do with the second one. That
--  is why job_run_details holds 14 days of history against a stated
--  retention of 2.
--
--  ## Fix
--
--  Keep the DELETEs in the function, where they work. Move the physical
--  shrink to its own schedule: pg_cron runs a bare command string
--  directly rather than through a function body, which is the documented
--  way to schedule VACUUM and the only context it can run in.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, cron, supabase_functions
AS $$
BEGIN
  -- Ordering note: these are independent, and each one must survive the
  -- others failing. patch_190 lost its cron prune to an error raised by
  -- unrelated work above it; that is a property of the ordering, not bad
  -- luck, so each statement now carries its own handler.

  -- pg_net's response log is transient by design — pg_net expires rows
  -- after a few hours and nothing in the app reads the table (verified by
  -- grep across lib/, supabase/ and database/: the only references are
  -- this patch and patch_190/191).
  BEGIN
    DELETE FROM net._http_response WHERE created < now() - interval '1 day';
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'prune net._http_response failed: %', SQLERRM;
  END;

  -- pg_cron keeps run history forever unless told otherwise.
  BEGIN
    DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'prune cron.job_run_details failed: %', SQLERRM;
  END;

  -- Database-webhook dispatch log. patch_190 predates this table growing
  -- (147k rows / 21 MB by August). Append-only, never read back.
  BEGIN
    DELETE FROM supabase_functions.hooks
     WHERE created_at < now() - interval '3 days';
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'prune supabase_functions.hooks failed: %', SQLERRM;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM authenticated, anon;

-- The physical shrink, as its own job. pg_cron executes this string as a
-- top-level command, NOT inside a function body — which is the whole
-- point, and the only context VACUUM is legal in.
--
-- Weekly, not nightly: VACUUM FULL takes an ACCESS EXCLUSIVE lock and
-- rewrites the table, and the DELETEs above are what actually keep size
-- bounded. This only reclaims the pages they leave behind.
--
-- 04:10 Sunday — after the 03:50 prune, so it compacts a table the prune
-- has already emptied.
SELECT cron.schedule(
  'vacuum-operational-logs',
  '10 4 * * 0',
  'VACUUM (FULL) net._http_response'
);

SELECT cron.schedule(
  'vacuum-cron-history',
  '20 4 * * 0',
  'VACUUM (FULL) cron.job_run_details'
);

-- ---------------------------------------------------------------------
--  Root cause of the VOLUME, unchanged and still worth a decision
--
--  patch_190 already flagged this and it is still true: `youtube-live-fast`
--  runs on `* * * * *`. Every minute, forever — 1,440 HTTP posts a day,
--  each writing one row to net._http_response AND one to
--  cron.job_run_details. These tables are not logging a problem, they are
--  logging that schedule.
--
--  This patch stops the logs eating the disk. It does NOT change the
--  schedule, because how fast a live stream should be noticed is a
--  product call. If three minutes is acceptable, changing that one line
--  cuts the write volume by two thirds:
--
--    SELECT cron.alter_job(
--      (SELECT jobid FROM cron.job WHERE jobname = 'youtube-live-fast'),
--      schedule => '*/3 * * * *'
--    );
-- ---------------------------------------------------------------------
