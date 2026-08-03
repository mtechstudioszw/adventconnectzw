-- ---------------------------------------------------------------------
--  STAFF ROLES + AUDIT LOG
--
--  WHY (audited 3 Aug 2026): there were no roles, no permissions and no
--  audit log. `assert_super_admin()` is a single boolean and the founder
--  is the only person holding it. Hiring anyone to manage the app meant
--  setting is_super_admin = true on their account, which grants the
--  power to ban any user, revoke church admins, broadcast a push to
--  every member and approve or reject anything — with no record of who
--  did it. That is the actual blocker to "non-technical people I hire to
--  manage my app", so it is fixed before any console UI is built.
--
--  DESIGN
--  * Additive and backwards compatible. All 35 existing admin RPCs call
--    assert_super_admin(); that keeps working unchanged, and now also
--    accepts a staff 'owner'. Nothing has to be migrated in one go.
--  * Four roles, least privilege first:
--      viewer     — read only. Safe for a new hire on day one.
--      moderator  — the daily job: reports, approvals, feedback.
--                   Contact details are MASKED for this role.
--      manager    — moderator + sees contact details + audit log.
--      owner      — everything, including ban and mass broadcast.
--  * Destructive power (ban, broadcast) is owner-only rather than
--    requiring two people to approve. At this team size two-person
--    approval is friction that gets worked around; the audit log is the
--    safeguard that actually survives contact with a small team.
-- ---------------------------------------------------------------------

-- =====================================================================
--  1. Staff
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.staff_members (
  user_id     UUID PRIMARY KEY
                REFERENCES public.profiles(id) ON DELETE CASCADE,
  role        TEXT NOT NULL
                CHECK (role IN ('viewer', 'moderator', 'manager', 'owner')),
  added_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Soft-disable rather than delete: someone who leaves should stop
  -- having access without their history in the audit log going anonymous.
  disabled_at TIMESTAMPTZ,
  note        TEXT
);

COMMENT ON TABLE public.staff_members IS
  'Who may use the admin console, and how much of it. Written only by '
  'admin_set_staff_role(), which is owner-only.';

CREATE INDEX IF NOT EXISTS staff_members_role_idx
  ON public.staff_members (role) WHERE disabled_at IS NULL;

-- Rank so "at least moderator" is a comparison, not a list of strings
-- that someone will forget to update when a role is added.
CREATE OR REPLACE FUNCTION public.staff_rank(p_role TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE p_role
    WHEN 'viewer'    THEN 1
    WHEN 'moderator' THEN 2
    WHEN 'manager'   THEN 3
    WHEN 'owner'     THEN 4
    ELSE 0
  END;
$function$;

-- The caller's effective role, or NULL if they are not staff.
CREATE OR REPLACE FUNCTION public.current_staff_role()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_role   TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT s.role INTO v_role
    FROM public.staff_members s
   WHERE s.user_id = v_caller
     AND s.disabled_at IS NULL;

  -- The legacy flag still counts as owner, so the founder (and the live
  -- console) keep working before anyone is added to staff_members.
  IF v_role IS NULL THEN
    SELECT CASE WHEN COALESCE(p.is_super_admin, FALSE) THEN 'owner' END
      INTO v_role
      FROM public.profiles p
     WHERE p.id = v_caller;
  END IF;

  RETURN v_role;
END;
$function$;

-- Gate for every admin action. Raises 42501 exactly like
-- assert_super_admin() so existing client error handling still works.
CREATE OR REPLACE FUNCTION public.assert_staff(p_min_role TEXT DEFAULT 'moderator')
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_role TEXT := public.current_staff_role();
BEGIN
  IF v_role IS NULL
     OR public.staff_rank(v_role) < public.staff_rank(p_min_role) THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
END;
$function$;

-- Backwards compatible: all 35 existing RPCs call this. It now also
-- accepts a staff 'owner', so staff_members can take over gradually
-- instead of in one risky sweep.
CREATE OR REPLACE FUNCTION public.assert_super_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF public.current_staff_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
END;
$function$;

-- May the caller see members' email / phone? Moderators may not — they
-- can do the whole moderation job without contact details, and the
-- fewer people holding PII the better.
CREATE OR REPLACE FUNCTION public.staff_can_see_pii()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
  SELECT public.staff_rank(public.current_staff_role())
         >= public.staff_rank('manager');
$function$;

-- Seed the founder as owner from the existing flag, so nothing depends
-- on remembering to do it by hand.
INSERT INTO public.staff_members (user_id, role, note)
SELECT p.id, 'owner', 'Seeded from is_super_admin, 3 Aug 2026'
  FROM public.profiles p
 WHERE COALESCE(p.is_super_admin, FALSE)
ON CONFLICT (user_id) DO NOTHING;

-- =====================================================================
--  2. Audit log
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id          BIGSERIAL PRIMARY KEY,
  actor_id    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- Denormalised on purpose: if the account is later deleted, the log
  -- must still say who did it. An audit trail that forgets is not one.
  actor_name  TEXT,
  actor_role  TEXT,
  action      TEXT NOT NULL,
  target_type TEXT,
  target_id   TEXT,
  before      JSONB,
  after       JSONB,
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS admin_audit_log_created_idx
  ON public.admin_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS admin_audit_log_actor_idx
  ON public.admin_audit_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS admin_audit_log_target_idx
  ON public.admin_audit_log (target_type, target_id);

-- Record one staff action. Call from inside admin RPCs.
CREATE OR REPLACE FUNCTION public.log_admin_action(
  p_action      TEXT,
  p_target_type TEXT DEFAULT NULL,
  p_target_id   TEXT DEFAULT NULL,
  p_before      JSONB DEFAULT NULL,
  p_after       JSONB DEFAULT NULL,
  p_note        TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_name   TEXT;
BEGIN
  SELECT p.full_name INTO v_name
    FROM public.profiles p WHERE p.id = v_caller;

  INSERT INTO public.admin_audit_log
    (actor_id, actor_name, actor_role, action, target_type, target_id,
     before, after, note)
  VALUES
    (v_caller, v_name, public.current_staff_role(), p_action,
     p_target_type, p_target_id, p_before, p_after, p_note);
END;
$function$;

-- =====================================================================
--  3. Managing staff (owner only) + reading the log
-- =====================================================================

CREATE OR REPLACE FUNCTION public.admin_list_staff()
RETURNS TABLE (
  user_id     UUID,
  full_name   TEXT,
  email       TEXT,
  role        TEXT,
  added_at    TIMESTAMPTZ,
  disabled    BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_staff('manager');
  RETURN QUERY
  SELECT s.user_id,
         p.full_name,
         CASE WHEN public.staff_can_see_pii() THEN u.email ELSE NULL END,
         s.role,
         s.added_at,
         s.disabled_at IS NOT NULL
    FROM public.staff_members s
    JOIN public.profiles p ON p.id = s.user_id
    LEFT JOIN auth.users u ON u.id = s.user_id
   ORDER BY public.staff_rank(s.role) DESC, s.added_at;
END;
$function$;

-- Add, promote, demote or disable a staff member. Owner only.
CREATE OR REPLACE FUNCTION public.admin_set_staff_role(
  p_user UUID,
  p_role TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_before TEXT;
  v_owners INT;
BEGIN
  PERFORM public.assert_staff('owner');

  IF p_role IS NOT NULL AND public.staff_rank(p_role) = 0 THEN
    RAISE EXCEPTION 'Unknown role %.', p_role USING ERRCODE = '22023';
  END IF;

  SELECT s.role INTO v_before
    FROM public.staff_members s WHERE s.user_id = p_user;

  -- Never let the last owner remove themselves — that locks everyone
  -- out of the console permanently, with no way back in from the app.
  IF v_before = 'owner' AND p_role IS DISTINCT FROM 'owner' THEN
    SELECT COUNT(*) INTO v_owners
      FROM public.staff_members
     WHERE role = 'owner' AND disabled_at IS NULL;
    IF v_owners <= 1 THEN
      RAISE EXCEPTION 'There must always be at least one owner.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF p_role IS NULL THEN
    UPDATE public.staff_members
       SET disabled_at = NOW() WHERE user_id = p_user;
  ELSE
    INSERT INTO public.staff_members (user_id, role, added_by)
    VALUES (p_user, p_role, auth.uid())
    ON CONFLICT (user_id) DO UPDATE
      SET role = EXCLUDED.role, disabled_at = NULL;
  END IF;

  PERFORM public.log_admin_action(
    'staff.set_role', 'user', p_user::TEXT,
    jsonb_build_object('role', v_before),
    jsonb_build_object('role', p_role));
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_audit_log(
  p_limit  INT DEFAULT 100,
  p_action TEXT DEFAULT NULL
)
RETURNS TABLE (
  id          BIGINT,
  actor_name  TEXT,
  actor_role  TEXT,
  action      TEXT,
  target_type TEXT,
  target_id   TEXT,
  note        TEXT,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_staff('manager');
  p_limit := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
  RETURN QUERY
  SELECT a.id, a.actor_name, a.actor_role, a.action, a.target_type,
         a.target_id, a.note, a.created_at
    FROM public.admin_audit_log a
   WHERE p_action IS NULL OR a.action = p_action
   ORDER BY a.created_at DESC
   LIMIT p_limit;
END;
$function$;

-- =====================================================================
--  4. RLS + grants — no client writes anywhere
-- =====================================================================

ALTER TABLE public.staff_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Staff may see the roster through the RPC; the table itself stays shut
-- so nobody can enumerate staff by querying it directly.
-- Deliberately NO policies: only SECURITY DEFINER functions read/write.

REVOKE ALL ON public.staff_members FROM authenticated, anon;
REVOKE ALL ON public.admin_audit_log FROM authenticated, anon;

REVOKE ALL ON FUNCTION public.admin_set_staff_role(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.log_admin_action(TEXT, TEXT, TEXT, JSONB, JSONB, TEXT)
  FROM PUBLIC, authenticated, anon;

GRANT EXECUTE ON FUNCTION public.assert_staff(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_staff_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_can_see_pii() TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_rank(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_staff_role(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_audit_log(INT, TEXT) TO authenticated;
