-- ============================================================
--  ONE-TIME SPACE RECLAIM — adventconnectzw
--  23 Aug 2026.  DB at 412 MB of a 500 MB cap.
--
--  Run in Supabase Dashboard -> SQL Editor.
--  RUN THE STEPS IN ORDER — later steps need the headroom the
--  earlier ones free.
--
--  Nothing here deletes application data. Every table below is
--  Supabase's own transient logging. Verified by grep across
--  lib/, supabase/ and database/: nothing reads any of them.
--
--  The permanent fix for WHY they grew is a separate file:
--  database/patch_226_fix_log_retention.sql  — apply that too,
--  or you will be back here in three weeks.
-- ============================================================


-- ---------- STEP 1 — pg_net response log  (~111 MB) ----------
-- TRUNCATE, not DELETE + VACUUM FULL, and the distinction matters
-- here: VACUUM FULL rewrites the table into NEW pages before
-- freeing the old ones, so it needs ~111 MB of free disk to
-- compact a 111 MB table. You have ~88 MB. It would fail, or
-- fill the disk trying.
--
-- TRUNCATE drops the pages outright. No headroom needed, instant.
-- Safe because pg_net expires these rows after ~6 hours anyway —
-- the 690 live rows are this morning's, and nothing reads them.
TRUNCATE TABLE net._http_response;


-- ---------- STEP 2 — webhook dispatch log  (~21 MB) ----------
-- 147,493 rows back to 18 May. Append-only; the app never reads it.
TRUNCATE TABLE supabase_functions.hooks;
-- If STEP 2 errors with a foreign-key complaint, use this instead:
--   DELETE FROM supabase_functions.hooks;


-- ---------- STEP 3 — pg_cron run history  (~28 MB) ----------
-- Steps 1-2 have now freed ~130 MB, so this VACUUM FULL has room.
-- Run the two statements SEPARATELY — VACUUM cannot share a
-- transaction, which is the exact bug patch_226 fixes.
DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';

VACUUM (FULL) cron.job_run_details;


-- ---------- STEP 4 — reclaim bloat, deletes nothing ----------
-- Run one at a time. Each takes a brief exclusive lock on its
-- table; do it off-peak. No rows are removed by any of these.
VACUUM (FULL) public.youtube_videos;          -- 6,676 dead tuples
VACUUM (FULL) public.youtube_playlist_items;  -- 3,237 dead tuples
VACUUM (FULL) auth.refresh_tokens;            -- 2,848 dead tuples
VACUUM (FULL) public.notifications;


-- ---------- CHECK ----------
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
-- Expect roughly 230-250 MB, down from 412 MB.


-- ============================================================
--  NOT INCLUDED, ON PURPOSE
--
--  public.youtube_videos is your biggest table (154 MB, 64,990
--  rows, 54,367 of them older than a year) — but it is real Watch
--  content, not trash. A 2019 sermon is as watchable as a 2026 one.
--
--  Do NOT blank `description` to reclaim the 31 MB it occupies:
--  lib/screens/watch/video_player_screen.dart renders it AND scans
--  it for scripture references (tap-a-verse, line 190). Nulling it
--  breaks that feature silently.
--
--  If this table genuinely needs to shrink, the real question is
--  whether the sync should have ingested 65k videos at all.
--  Narrowing the scraper's playlist set is the fix; mass-deleting
--  rows is not.
--
--  public.notifications: only ~4,900 rows are older than 30 days
--  (~7 MB). Not worth a retention policy yet.
-- ============================================================
