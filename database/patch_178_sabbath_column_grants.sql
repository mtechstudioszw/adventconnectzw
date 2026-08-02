-- =====================================================================
--  PATCH 178 — grant SELECT on the two Sabbath columns
--
--  patch_132 revoked table-level SELECT on `profiles` and re-granted it
--  column by column, which makes new columns fail-closed: invisible to
--  `authenticated` until somebody remembers to grant them. patch_134
--  remembered. patch_169 did not, so `sabbath_mode_enabled` and
--  `sabbath_quiet_until` have been unreadable since they were added.
--
--  Nothing in the app reads them today (SabbathService only writes, and
--  the notifications guard is a trigger running as the table owner), so
--  this is closing a trap rather than fixing a live outage: the first
--  `select('*')` on profiles — or any settings screen that wants to show
--  the current Sabbath-mode state — would have failed with a bare
--  "permission denied for table profiles" and sent someone hunting
--  through RLS policies for a privilege bug.
--
--  Neither column is sensitive: one is a boolean the user set themselves,
--  the other is a timestamp derived from their province's sundown.
-- =====================================================================

GRANT SELECT (sabbath_mode_enabled, sabbath_quiet_until)
  ON public.profiles TO authenticated;
