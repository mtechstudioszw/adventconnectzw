-- =====================================================================
--  PATCH 287 — personal accounts by default: followers OFF
--  STATUS: not yet applied
--
--  Owner, 29 Oct 2026: "every person gets a default personal account which
--  doesn't allow people to follow you, but you switch to allow people to
--  follow you."
--
--  Friends (two-way, `friendships`) stay the default way to connect.
--  Following (one-way, `follows`, patch_274) becomes opt-in: a member
--  turns "Allow followers" on in Settings → Privacy — meant for pastors,
--  leaders, musicians and ministries who post publicly. Pages can always
--  be followed (unchanged).
--
--  What this changes:
--    * profiles.who_can_follow DEFAULT 'everyone' → 'nobody', so new
--      accounts start with followers off.
--    * Every existing 'everyone' row → 'nobody'. Checked before writing
--      this: 687 profiles, all 'everyone', and ZERO rows in `follows` —
--      so nobody loses a single follower. Anyone on 'friends' is left
--      as they chose.
--
--  What it does not change: the follows_set_status() guard (patch_282)
--  already refuses a follow when who_can_follow = 'nobody', so the server
--  enforces this on its own; no new column, no new grant (SELECT on
--  who_can_follow was granted in patch_282).
--
--  CLAUDE.md checklist: no new profiles column; the privilege trigger is
--  not involved (who_can_follow is the member's own setting); no new
--  BEFORE trigger.
-- =====================================================================

BEGIN;

ALTER TABLE public.profiles
  ALTER COLUMN who_can_follow SET DEFAULT 'nobody';

UPDATE public.profiles
   SET who_can_follow = 'nobody'
 WHERE who_can_follow = 'everyone';

NOTIFY pgrst, 'reload schema';

COMMIT;
