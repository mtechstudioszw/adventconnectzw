-- =====================================================================
--  PATCH 100 — soft-update grace window
--
--  Extends the force-update gate (patch_091) with a 5-day grace window.
--
--    min_build_android    — HARD floor. Builds below this are blocked
--                           immediately (emergency lever). Unchanged.
--    latest_build_android  — newest published Android versionCode. Builds
--                           below this (but >= the floor) get a dismissible
--                           "update available — N days left" nudge instead
--                           of an immediate block.
--    update_grace_days     — how many days the nudge shows before it
--                           escalates to a hard block. Default 5.
--
--  Release flow: bump pubspec build number + kAppBuildNumber, then set
--  latest_build_android to that number. Everyone on an older build is
--  nudged for `update_grace_days` days (counted from when THEIR device
--  first saw the new build), then hard-blocked. Only raise
--  min_build_android when you must force everyone off a build immediately
--  (security/data bug) with no grace.
--
--  Seeded so the CURRENT build (versionCode 7) is never nagged:
--  latest_build_android = 7.
-- =====================================================================

INSERT INTO public.app_config (key, value) VALUES
  ('latest_build_android', '7'),
  ('update_grace_days', '5')
ON CONFLICT (key) DO NOTHING;
