-- =====================================================================
--  PATCH 045 — profiles.show_age (tester bug #7)
--
--  Lets a user hide their age on their public profile. Defaults TRUE
--  (current behaviour — age shown) so existing users are unaffected.
--  The app writes it from Edit Profile and the user_profile screen
--  only renders age when show_age is true (or you're viewing your own).
--
--  IDEMPOTENT.
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_age BOOLEAN NOT NULL DEFAULT TRUE;
