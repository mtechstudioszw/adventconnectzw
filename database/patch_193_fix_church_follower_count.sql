-- =====================================================================
--  patch_193 — the church follower count has been frozen since patch_121
--
--  Reported as "the number of members on a church is lying".
--  Measured before the fix: 63 churches wrong, 82 follows never counted.
--
--  ## What happened
--
--  Two triggers on the same column, fighting.
--
--  `bump_church_follower_count()` (schema.sql, hardened in patch_019) is
--  AFTER INSERT OR DELETE on `church_followers`, and does
--  `UPDATE public.churches SET follower_count = follower_count + 1`.
--
--  `churches_protect_columns()` (patch_121) is BEFORE UPDATE on
--  `churches`, and exists to stop a church admin editing their own row
--  into `verified = true` or a made-up follower count. It decides who is
--  "the app" with `auth.uid() IS NOT NULL`:
--
--      IF auth.uid() IS NOT NULL THEN
--        NEW.follower_count := OLD.follower_count;   -- freeze
--
--  `SECURITY DEFINER` changes the effective ROLE. It does not change
--  `auth.uid()`, which reads the JWT claim off the session and is still
--  the signed-in member. So the counter's own UPDATE walked into the
--  guard, was told it was an app-side edit, and had its increment
--  reverted — every single time, silently, since patch_121 shipped.
--
--  Nothing errored. The INSERT into `church_followers` succeeded, the
--  member saw themselves following the church, and the number on the card
--  never moved.
--
--  ## The fix
--
--  Ask `current_user`, not `auth.uid()`.
--
--  PostgREST runs app requests as the `authenticated` role. Inside a
--  SECURITY DEFINER function `current_user` is the function's owner, and
--  the service role connects as `service_role`. So `current_user` tells
--  the three callers apart exactly, and — unlike a session GUC — a client
--  cannot change it. Verified before writing this: `bump_church_follower_count`
--  is the ONLY function in the schema that updates `public.churches`, so
--  no other privileged path is newly exempted by this.
--
--  Then backfill, because the rows that were dropped are not recoverable
--  from anywhere except `church_followers` itself — which is, thankfully,
--  the authoritative record and was never touched.
-- =====================================================================

-- ---- 1. The guard, asking the right question -------------------------

CREATE OR REPLACE FUNCTION public.churches_protect_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
BEGIN
  -- App-side edits (church admins, via PostgREST) may not touch trust /
  -- rollup / identity columns.
  --
  -- `current_user` and NOT `auth.uid()`: the follower-count trigger runs
  -- SECURITY DEFINER, so its current_user is the owner, but auth.uid() is
  -- still the member who pressed Follow. Testing auth.uid() therefore
  -- caught the counter's own write and reverted it. See the header.
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.verified       := OLD.verified;
    NEW.status         := OLD.status;
    NEW.follower_count := OLD.follower_count;
    NEW.members_count  := OLD.members_count;
    NEW.created_at     := OLD.created_at;
  END IF;
  RETURN NEW;
END;
$$;

-- ---- 2. Backfill what was dropped ------------------------------------
-- `church_followers` is the source of truth and is unaffected by the bug,
-- so every lost increment can be recomputed exactly. Touches only the
-- rows that are actually wrong.

UPDATE public.churches c
   SET follower_count = f.n
  FROM (
    SELECT ch.id, count(cf.id) AS n
      FROM public.churches ch
      LEFT JOIN public.church_followers cf ON cf.church_id = ch.id
     GROUP BY ch.id
  ) f
 WHERE f.id = c.id
   AND c.follower_count <> f.n;

-- ---- 3. Prove it ------------------------------------------------------
-- Zero rows means stored and actual agree everywhere.

DO $$
DECLARE
  v_wrong integer;
BEGIN
  SELECT count(*) INTO v_wrong
    FROM public.churches c
   WHERE c.follower_count <> (
     SELECT count(*) FROM public.church_followers f WHERE f.church_id = c.id
   );
  IF v_wrong <> 0 THEN
    RAISE EXCEPTION 'patch_193: % churches still have a wrong follower_count', v_wrong;
  END IF;
  RAISE NOTICE 'patch_193: follower_count reconciled for every church';
END;
$$;
