-- =====================================================================
--  PATCH 190 — Stop the log tables eating the database
--
--  Measured 4 Aug 2026. Database was ~340 MB on a 500 MB plan, and TWO
--  THIRDS of it was logs holding no user data at all:
--
--    net._http_response     146 MB  — for 824 live rows. Pure bloat:
--                                     pg_net prunes the ROWS but nothing
--                                     ever reclaimed the pages.
--    cron.job_run_details    54 MB  — 63,297 rows back to 17 May.
--                                     pg_cron never prunes this at all.
--
--  Truncating the first and vacuuming the second took the database to
--  174 MB without touching a single row a member could see.
--
--  ## Why it got that big — the part worth fixing properly
--
--  `youtube-live-fast` runs on `* * * * *`. Every minute, forever. That is
--  1,440 HTTP posts a day, and EACH ONE writes a row to net._http_response
--  AND a row to cron.job_run_details. Those two tables are not really
--  logging a problem, they are logging that schedule.
--
--  This patch keeps the tables small. It does NOT change the schedule —
--  that is a product call about how fast a live stream should be noticed,
--  and it belongs to the founder. But if the answer is "three minutes is
--  fine", changing that one line cuts the write volume by two thirds and
--  is worth more than this patch is.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, cron
AS $$
DECLARE
  v_resp_bytes BIGINT;
BEGIN
  -- pg_net's response log is transient by design: nothing reads it except
  -- a human debugging a webhook, and only ever the last few hours of it.
  -- DELETE would leave the pages behind (that is how it reached 146 MB for
  -- 824 rows), so anything older than a day goes and the table is
  -- physically shrunk when it has clearly bloated.
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';

  SELECT pg_total_relation_size('net._http_response') INTO v_resp_bytes;
  -- 20 MB for a table that should hold a few hundred rows means dead
  -- pages, not data. VACUUM FULL takes an exclusive lock, so it is gated
  -- behind that check rather than run every night for no reason.
  IF v_resp_bytes > 20 * 1024 * 1024 THEN
    EXECUTE 'VACUUM FULL net._http_response';
  END IF;

  -- pg_cron keeps run history forever unless told otherwise. Two days is
  -- enough to answer "did last night's job run?", which is the only
  -- question anyone asks of it.
  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';
END;
$$;

REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM authenticated, anon;

-- 03:50 — after cleanup-expired-content (03:10) and purge-storage (03:30),
-- so it sweeps up the rows those two generate on their way out.
SELECT cron.schedule(
  'prune-operational-logs',
  '50 3 * * *',
  $$SELECT public.prune_operational_logs();$$
);
