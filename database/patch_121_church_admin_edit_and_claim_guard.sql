-- =====================================================================
--  PATCH 121 — Church-admin self-service edit + claim rate-limiting.
--
--  Three things:
--   1. get_church_claim_state(church_id) — a SECURITY DEFINER reader that
--      tells the app EXACTLY which claim message to show without leaking
--      other users' pending rows (RLS hides those). Drives claim_church_screen.
--   2. church_admins_enforce_single_claim — BEFORE INSERT guard so the
--      one-church-per-user / already-claimed / under-review rules hold even
--      if a client skips the in-app gate. Mirrors the messages the app shows.
--   3. churches UPDATE policy for approved church admins + a column guard
--      so admins can edit their church (description, address, photos, etc.)
--      but NOT the trust/rollup columns (verified, status, follower_count …).
--
--  Apply:  POST /v1/projects/<ref>/database/query  (service / management API)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Claim-state reader (no PII — booleans + counts only)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_church_claim_state(p_church_id bigint)
RETURNS TABLE (
  church_has_approved_admin boolean,
  church_has_pending_other  boolean,
  my_status_for_church      text,
  my_other_pending_count    integer,
  my_other_approved_count   integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  RETURN QUERY
  SELECT
    EXISTS (
      SELECT 1 FROM public.church_admins
       WHERE church_id = p_church_id AND status = 'approved'
    ),
    EXISTS (
      SELECT 1 FROM public.church_admins
       WHERE church_id = p_church_id AND status = 'pending'
         AND user_id <> COALESCE(v_uid, '00000000-0000-0000-0000-000000000000'::uuid)
    ),
    (
      SELECT ca.status FROM public.church_admins ca
       WHERE ca.church_id = p_church_id AND ca.user_id = v_uid
       ORDER BY ca.created_at DESC
       LIMIT 1
    ),
    (
      SELECT COUNT(*)::int FROM public.church_admins
       WHERE user_id = v_uid AND church_id <> p_church_id AND status = 'pending'
    ),
    (
      SELECT COUNT(*)::int FROM public.church_admins
       WHERE user_id = v_uid AND church_id <> p_church_id AND status = 'approved'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_church_claim_state(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_church_claim_state(bigint) TO authenticated;


-- ---------------------------------------------------------------------
-- 2. One-church-per-user / already-claimed guard (defense in depth)
--    Runs BEFORE INSERT (after the pin-pending trigger). Same-church
--    re-submit via upsert stays allowed (only DIFFERENT churches count).
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

DROP TRIGGER IF EXISTS trg_church_admins_single_claim_guard ON public.church_admins;
CREATE TRIGGER trg_church_admins_single_claim_guard
  BEFORE INSERT ON public.church_admins
  FOR EACH ROW EXECUTE FUNCTION public.church_admins_enforce_single_claim();


-- ---------------------------------------------------------------------
-- 3. Let approved church admins edit their own church row.
--    A column guard keeps trust/rollup fields read-only from the app.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "churches_update_admin" ON public.churches;
CREATE POLICY "churches_update_admin" ON public.churches
  FOR UPDATE
  USING (public.is_approved_church_admin(id))
  WITH CHECK (public.is_approved_church_admin(id));

CREATE OR REPLACE FUNCTION public.churches_protect_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
BEGIN
  -- App-side edits (any authenticated caller, i.e. church admins) may not
  -- touch trust / rollup / identity columns. Super-admin tooling uses the
  -- service role (auth.uid() IS NULL) and is exempt.
  IF auth.uid() IS NOT NULL THEN
    NEW.verified       := OLD.verified;
    NEW.status         := OLD.status;
    NEW.follower_count := OLD.follower_count;
    NEW.members_count  := OLD.members_count;
    NEW.created_at     := OLD.created_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_churches_protect_columns ON public.churches;
CREATE TRIGGER trg_churches_protect_columns
  BEFORE UPDATE ON public.churches
  FOR EACH ROW EXECUTE FUNCTION public.churches_protect_columns();
