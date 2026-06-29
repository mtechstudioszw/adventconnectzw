-- =====================================================================
--  PATCH 153 — Manage APPROVED church admins from the web admin console.
--
--  patch_112 covered the *pending* claim queue (approve / reject). This
--  adds management of admins who are already APPROVED:
--    • list approved (and previously removed) church admins
--    • send a warning notification to a church admin
--    • REMOVE a church admin — and make the removal impossible to bypass
--
--  ── "No bypass" guarantee ──────────────────────────────────────────
--  Removal sets status = 'revoked' (a new terminal state); we never
--  DELETE the row. Every church-admin privilege in the schema is gated
--  on status = 'approved' (channel posting, branded posts, member list,
--  admin stats, member count, verified badge, church-row edit), so a
--  revoked admin instantly loses ALL powers.
--
--  A revoked admin cannot restore themselves:
--    1. church_admins_block_status_self_update (patch_028) forces
--       NEW.status := OLD.status for any non-super-admin UPDATE — so the
--       in-app "re-claim" upsert (INSERT … ON CONFLICT DO UPDATE on the
--       UNIQUE(church_id,user_id) key) can never flip 'revoked' back to
--       'pending'.
--    2. We additionally hard-block the INSERT path: a revoked user
--       attempting to re-claim THAT church is rejected outright
--       (CHURCH_CLAIM_REVOKED) by the single-claim guard below.
--  Only the super admin (service-side, via the RPCs here) can change a
--  revoked row — e.g. admin_approve_church_admin() re-instates them.
--
--  Every function is SECURITY DEFINER + assert_super_admin(): the web
--  client only holds the public anon key, so the server is the sole gate.
--
--  Apply:  POST /v1/projects/<ref>/database/query (service / mgmt API),
--          or run in the Supabase SQL editor. Apply BEFORE deploying the
--          matching admin-web/ build, which calls these RPCs.
--  IDEMPOTENT: CREATE OR REPLACE + IF EXISTS throughout.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Allow the new terminal status value.
-- ---------------------------------------------------------------------
ALTER TABLE public.church_admins
  DROP CONSTRAINT IF EXISTS church_admins_status_check;
ALTER TABLE public.church_admins
  ADD CONSTRAINT church_admins_status_check
  CHECK (status IN ('pending','approved','rejected','revoked'));


-- ---------------------------------------------------------------------
-- 1. List church admins (approved by default; 'revoked' / 'all' too).
--    Joins the real account identity (profiles + auth email) alongside
--    the applicant_* fields they supplied when claiming, plus the church
--    and its follower count for context.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_church_admins(
  p_status TEXT DEFAULT 'approved',   -- 'approved' | 'revoked' | 'all'
  p_search TEXT DEFAULT '',
  p_limit  INT  DEFAULT 200
)
RETURNS TABLE (
  id               BIGINT,
  church_id        BIGINT,
  user_id          UUID,
  role             TEXT,
  status           TEXT,
  applicant_name   TEXT,
  applicant_phone  TEXT,
  applicant_email  TEXT,
  profile_name     TEXT,
  profile_email    TEXT,
  approved_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ,
  rejection_reason TEXT,
  church_name      TEXT,
  church_city      TEXT,
  follower_count   INT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_q TEXT := '%' || btrim(COALESCE(p_search,'')) || '%';
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT ca.id, ca.church_id, ca.user_id, ca.role, ca.status,
           ca.applicant_name, ca.applicant_phone, ca.applicant_email,
           COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS profile_name,
           u.email::text AS profile_email,
           ca.approved_at, ca.created_at, ca.rejection_reason,
           c.name, c.city,
           (SELECT COUNT(*)::int FROM public.church_followers cf
             WHERE cf.church_id = ca.church_id) AS follower_count
      FROM public.church_admins ca
      JOIN public.churches  c ON c.id = ca.church_id
      LEFT JOIN public.profiles p ON p.id = ca.user_id
      LEFT JOIN auth.users    u ON u.id = ca.user_id
     WHERE (p_status = 'all' OR ca.status = p_status)
       AND (
         btrim(COALESCE(p_search,'')) = ''
         OR c.name ILIKE v_q
         OR ca.applicant_name ILIKE v_q
         OR p.full_name ILIKE v_q
         OR u.email ILIKE v_q
       )
     ORDER BY (ca.status = 'approved') DESC,
              COALESCE(ca.approved_at, ca.created_at) DESC
     LIMIT GREATEST(p_limit, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_church_admins(TEXT, TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_church_admins(TEXT, TEXT, INT) TO authenticated;


-- ---------------------------------------------------------------------
-- 2. Warn a church admin — drops a notification into their feed (which
--    the existing notify-fcm webhook also pushes). Does NOT change their
--    status; it's a formal nudge before removal.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_warn_church_admin(
  p_id      BIGINT,
  p_message TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_user  UUID;
  v_clean TEXT := NULLIF(btrim(COALESCE(p_message,'')), '');
BEGIN
  PERFORM public.assert_super_admin();
  IF v_clean IS NULL THEN
    RAISE EXCEPTION 'Warning message cannot be empty.';
  END IF;

  SELECT user_id INTO v_user FROM public.church_admins WHERE id = p_id;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Church admin % not found.', p_id;
  END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_user,
    'Warning from the Advent Connect team',
    v_clean,
    'church_admin_warning',
    p_id::text,
    'church_admin'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_warn_church_admin(BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_warn_church_admin(BIGINT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------
-- 3. Remove (revoke) a church admin — strips every privilege and frees
--    the church to be claimed by a legitimate new admin (a revoked row
--    drops out of idx_church_admins_one_primary_per_church). The user is
--    notified. status='revoked' is sticky (see header) so they cannot
--    re-grant themselves.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_revoke_church_admin(
  p_id     BIGINT,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_user   UUID;
  v_church TEXT;
  v_clean  TEXT := NULLIF(btrim(COALESCE(p_reason,'')), '');
BEGIN
  PERFORM public.assert_super_admin();

  SELECT ca.user_id, c.name
    INTO v_user, v_church
    FROM public.church_admins ca
    JOIN public.churches c ON c.id = ca.church_id
   WHERE ca.id = p_id;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Church admin % not found.', p_id;
  END IF;

  UPDATE public.church_admins
     SET status           = 'revoked',
         rejection_reason = v_clean
   WHERE id = p_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_user,
    'Church admin access removed',
    'Your admin access for ' || COALESCE(v_church, 'your church')
      || ' on Advent Connect has been removed by the team.'
      || CASE WHEN v_clean IS NOT NULL THEN ' Reason: ' || v_clean ELSE '' END
      || ' If you believe this is a mistake, contact support.',
    'church_admin_revoked',
    p_id::text,
    'church_admin'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_revoke_church_admin(BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_revoke_church_admin(BIGINT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------
-- 4. Harden the claim guard: a REVOKED admin can never re-claim the same
--    church. Defense-in-depth on top of church_admins_block_status_self_update
--    (which already keeps a revoked row revoked on the upsert UPDATE path).
--    Re-creates patch_121's function with one extra check; everything else
--    is unchanged.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.church_admins_enforce_single_claim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  -- Service-role / system inserts bypass the guard.
  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;

  -- This user was REMOVED as admin of this church → permanent block.
  IF EXISTS (
    SELECT 1 FROM public.church_admins
     WHERE church_id = NEW.church_id AND user_id = v_uid AND status = 'revoked'
  ) THEN
    RAISE EXCEPTION 'CHURCH_CLAIM_REVOKED' USING ERRCODE = 'check_violation';
  END IF;

  -- Church already has an approved admin (someone else) → already claimed.
  IF EXISTS (
    SELECT 1 FROM public.church_admins
     WHERE church_id = NEW.church_id AND status = 'approved' AND user_id <> v_uid
  ) THEN
    RAISE EXCEPTION 'CHURCH_ALREADY_CLAIMED' USING ERRCODE = 'check_violation';
  END IF;

  -- Church has a pending claim by someone else → under review.
  IF EXISTS (
    SELECT 1 FROM public.church_admins
     WHERE church_id = NEW.church_id AND status = 'pending' AND user_id <> v_uid
  ) THEN
    RAISE EXCEPTION 'CHURCH_CLAIM_UNDER_REVIEW' USING ERRCODE = 'check_violation';
  END IF;

  -- Caller already holds a pending/approved claim on a DIFFERENT church.
  IF EXISTS (
    SELECT 1 FROM public.church_admins
     WHERE user_id = v_uid AND church_id <> NEW.church_id
       AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'USER_ALREADY_HAS_CLAIM' USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;
-- Trigger already exists from patch_121; CREATE OR REPLACE updates the body.
