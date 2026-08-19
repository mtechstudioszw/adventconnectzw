-- =====================================================================
--  PATCH 225 — take TRUNCATE away from anon and authenticated, everywhere
--
--  Found while writing patch_224. app_config was not special: EVERY table
--  in the public schema grants TRUNCATE to both client roles — 166
--  table/role pairs, including profiles, messages, conversations, posts,
--  churches, orders, subscriptions and the e2ee key tables.
--
--  This is the Supabase default. Creating a table in the SQL editor
--  grants ALL to anon and authenticated, on the understanding that RLS
--  restrains what those roles can actually touch. For INSERT, SELECT,
--  UPDATE and DELETE that understanding is correct: each is filtered
--  row-by-row by policy, which is why DELETE is left alone here — the app
--  genuinely deletes posts, messages and listings, and RLS confines each
--  one to its owner.
--
--  TRUNCATE is the exception, and it is the whole point of this patch:
--
--    TRUNCATE IS NOT SUBJECT TO ROW-LEVEL SECURITY.
--
--  Postgres checks the table-level privilege and nothing else. A role
--  holding TRUNCATE empties the table in full, however many policies
--  guard its rows, and it does not fire row triggers or leave the rows
--  recoverable the way a DELETE inside a transaction would.
--
--  IS IT EXPLOITABLE TODAY? Not through any route we ship. PostgREST
--  exposes no TRUNCATE verb, so an anon key plus the REST API cannot
--  reach it. The risk is what the grant permits if anything ever changes:
--  a SECURITY INVOKER function that truncates, a direct connection issued
--  under one of these roles, or a future Supabase feature that widens the
--  surface. The app has never truncated a table from a client and never
--  will — no client-side feature is expressible as "empty this table" —
--  so the grant buys nothing and risks everything on it.
--
--  WHAT THIS CHANGES FOR THE APP: nothing. If revoking TRUNCATE breaks a
--  feature, that feature was emptying a whole table from a phone, which
--  would be the actual bug.
--
--  IDEMPOTENT: yes. Re-running revokes what is already revoked.
-- =====================================================================

DO $$
DECLARE
  r RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR r IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       -- r/p = ordinary + partitioned tables, which is where the real risk
       -- is. 'v' (views) are included only so the verification query below
       -- can return a clean zero: Postgres cannot TRUNCATE a view at all,
       -- so those grants were inert — but leaving four stragglers behind
       -- makes the check look like it half-worked, and the next person to
       -- run it has to re-derive why.
       AND c.relkind IN ('r', 'p', 'v')
     ORDER BY c.relname
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE ON public.%I FROM anon, authenticated',
      r.relname
    );
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE 'TRUNCATE revoked from anon+authenticated on % tables', v_count;
END $$;

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- SELECT count(*) AS remaining_truncate_grants
--   FROM information_schema.role_table_grants
--  WHERE table_schema='public'
--    AND grantee IN ('anon','authenticated')
--    AND privilege_type = 'TRUNCATE';
--   -- expect: 0
--
-- SELECT count(*) AS delete_grants_kept
--   FROM information_schema.role_table_grants
--  WHERE table_schema='public'
--    AND grantee IN ('anon','authenticated')
--    AND privilege_type = 'DELETE';
--   -- expect: UNCHANGED — DELETE is governed by RLS and the app needs it.
--
--  NOTE FOR NEW TABLES: Supabase's default privileges will grant TRUNCATE
--  again on anything created later through the dashboard. Either re-run
--  this patch after adding tables, or set it once and for all with:
--    ALTER DEFAULT PRIVILEGES IN SCHEMA public
--      REVOKE TRUNCATE ON TABLES FROM anon, authenticated;
--  (left out here deliberately — default-privilege changes apply only to
--  the role that runs them, so it needs running as the same role that
--  creates tables, and getting that wrong gives a false sense of cover.)
