-- patch_198: tell the client whether *this* caller is actually blocked.
--
-- THE BUG
--
-- patch_187 exempts super admins from maintenance on purpose — "somebody has
-- to be able to fix whatever the maintenance is for, and to turn it back off".
-- `maintenance_active()` honours that: it ANDs in `NOT is_super_admin()`.
--
-- `maintenance_status()` does NOT. It returns the raw `maintenance_mode` flag,
-- and that is the function the app calls at splash to decide whether to show
-- the blocking screen. So the moment the founder turns maintenance on, the
-- founder's own app gates them out of it — the exact opposite of the exemption
-- the patch was careful to write. Nobody hit it yet because the check only ran
-- at cold start; wiring a live in-session gate would have made it constant.
--
-- THE FIX
--
-- One more column. `active` keeps meaning "is maintenance on" — the admin
-- console needs that, and an owner reading their own console must see the
-- truth rather than their own exemption. `blocked` means "is the caller in
-- front of me shut out", which is the only question a client should gate on.
--
-- Adding a column to a RETURNS TABLE needs a DROP: `CREATE OR REPLACE` refuses
-- a changed signature. Dropping is safe here — every caller reads columns by
-- name, and both existing names survive.

DROP FUNCTION IF EXISTS public.maintenance_status();

CREATE OR REPLACE FUNCTION public.maintenance_status()
RETURNS TABLE (
  active  boolean,
  blocked boolean,
  message text,
  ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    -- Is maintenance on at all. What the admin console reports.
    COALESCE((SELECT c.value = '1' FROM public.app_config c
               WHERE c.key = 'maintenance_mode'), false),
    -- Is THIS caller shut out. Identical to `maintenance_active()`, which is
    -- what the database triggers enforce — so the screen a member sees and
    -- the writes the server refuses can never disagree.
    public.maintenance_active(),
    COALESCE((SELECT NULLIF(btrim(c.value), '') FROM public.app_config c
               WHERE c.key = 'maintenance_message'),
             'Advent Connect is down for maintenance.'),
    (SELECT NULLIF(btrim(c.value), '')::timestamptz FROM public.app_config c
      WHERE c.key = 'maintenance_ends_at');
$$;

GRANT EXECUTE ON FUNCTION public.maintenance_status() TO authenticated, anon;

-- Older installed builds (1.3.1 and earlier) read only `active` and will keep
-- gating on the raw flag. That is the behaviour they already have; this patch
-- does not make them worse, and the next release reads `blocked`.
