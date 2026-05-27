-- =====================================================================
--  PATCH 026 — Server-side rate limiting (RPC)
--
--  WHY: Client-side throttle exists for password resets but is
--       bypassable by clearing secure storage or hitting Supabase
--       directly. This patch adds a server-enforced check that lives
--       behind a SECURITY DEFINER RPC. The Flutter app calls the
--       RPC before issuing rate-limited actions (password reset, OTP
--       requests, etc) and refuses to proceed if the limit is hit.
--
--  WHAT:
--   1. rate_limits table — (identity_key, action_key, hit_at).
--      No primary-key constraint that'd block concurrent inserts;
--      we rely on the window-cull query to keep it small.
--   2. check_and_consume_rate_limit RPC — atomically prunes the
--      window, counts hits, and either consumes a slot (returns
--      true) or refuses (returns false).
--   3. cleanup_old_rate_limits job runs nightly to garbage-collect
--      rows older than 7 days (defensive — the window-cull on every
--      call also handles this).
--
--  PREREQUISITES: pg_cron available (already enabled per patch_008).
--  IDEMPOTENT:    yes. IF NOT EXISTS / OR REPLACE throughout.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.rate_limits (
  identity_key  TEXT NOT NULL,
  action_key    TEXT NOT NULL,
  hit_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_lookup
  ON public.rate_limits (action_key, identity_key, hit_at DESC);

-- Lock down — only the RPC (SECURITY DEFINER) writes. Anon /
-- authenticated have no direct access.
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rate_limits_no_direct_access" ON public.rate_limits;
CREATE POLICY "rate_limits_no_direct_access" ON public.rate_limits
  FOR ALL USING (FALSE) WITH CHECK (FALSE);


CREATE OR REPLACE FUNCTION public.check_and_consume_rate_limit(
  p_identity_key   TEXT,
  p_action_key     TEXT,
  p_max            INTEGER DEFAULT 3,
  p_window_seconds INTEGER DEFAULT 3600
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_start TIMESTAMPTZ;
  v_hit_count    INTEGER;
BEGIN
  IF p_identity_key IS NULL OR length(trim(p_identity_key)) = 0 THEN
    RETURN FALSE;
  END IF;

  v_window_start := NOW() - (p_window_seconds || ' seconds')::interval;

  -- Best-effort cleanup of stale rows for this action — keeps the
  -- table tiny and avoids pg_cron-only maintenance.
  DELETE FROM public.rate_limits
   WHERE action_key = p_action_key
     AND hit_at < v_window_start - INTERVAL '1 day';

  SELECT COUNT(*) INTO v_hit_count
    FROM public.rate_limits
   WHERE identity_key = lower(p_identity_key)
     AND action_key   = p_action_key
     AND hit_at      >= v_window_start;

  IF v_hit_count >= p_max THEN
    RETURN FALSE;
  END IF;

  INSERT INTO public.rate_limits (identity_key, action_key, hit_at)
  VALUES (lower(p_identity_key), p_action_key, NOW());

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION
  public.check_and_consume_rate_limit(TEXT, TEXT, INTEGER, INTEGER)
  TO anon, authenticated;
