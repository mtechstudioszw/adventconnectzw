-- =====================================================================
--  PATCH 125 — server-side OTP/verification resend throttle
--
--  Bug (#9): the "resend code" cap lived only in app memory (_resendCount),
--  so closing + reopening the app reset it — a user could request endless
--  verification emails, burning the SMTP quota.
--
--  Fix: track resend attempts per email server-side. Allow 3 resends per
--  rolling hour; the 4th request locks that email out for 1 hour. The app
--  calls register_otp_resend(email) BEFORE auth.resend() and respects the
--  verdict. Keyed by email (survives app restart AND reinstall), unlike the
--  old client counter.
--
--  Pre-auth flow → the RPC is SECURITY DEFINER and granted to anon. The
--  table is RLS-locked with no policies, so it's only reachable through the
--  function. The function leaks nothing beyond allow/deny + a retry time.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.email_otp_throttle (
  email         TEXT PRIMARY KEY,
  attempts      INT NOT NULL DEFAULT 0,
  window_start  TIMESTAMPTZ NOT NULL DEFAULT now(),
  blocked_until TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.email_otp_throttle ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: only the SECURITY DEFINER function below touches it.

CREATE OR REPLACE FUNCTION public.register_otp_resend(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email   TEXT := lower(btrim(p_email));
  v_now     TIMESTAMPTZ := now();
  v_max     INT := 3;            -- resends allowed per window
  v_window  INTERVAL := interval '1 hour';
  v_lock    INTERVAL := interval '1 hour';
  rec       public.email_otp_throttle%ROWTYPE;
  v_attempts INT;
  v_start    TIMESTAMPTZ;
BEGIN
  IF v_email IS NULL OR v_email = '' THEN
    RETURN jsonb_build_object('allowed', true, 'remaining', v_max);
  END IF;

  SELECT * INTO rec FROM public.email_otp_throttle
    WHERE email = v_email FOR UPDATE;

  -- Still inside an active lockout → deny.
  IF rec.blocked_until IS NOT NULL AND rec.blocked_until > v_now THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'retry_after_seconds',
      ceil(extract(epoch FROM (rec.blocked_until - v_now)))::int);
  END IF;

  -- Fresh window if we've never seen this email or the hour has rolled over.
  IF rec.email IS NULL OR rec.window_start < v_now - v_window THEN
    v_attempts := 1;
    v_start := v_now;
  ELSE
    v_attempts := rec.attempts + 1;
    v_start := rec.window_start;
  END IF;

  -- Over the cap → start a 1-hour lockout and deny this request.
  IF v_attempts > v_max THEN
    INSERT INTO public.email_otp_throttle (email, attempts, window_start, blocked_until, updated_at)
    VALUES (v_email, v_attempts, v_start, v_now + v_lock, v_now)
    ON CONFLICT (email) DO UPDATE
      SET attempts = EXCLUDED.attempts,
          blocked_until = EXCLUDED.blocked_until,
          updated_at = v_now;
    RETURN jsonb_build_object(
      'allowed', false,
      'retry_after_seconds', ceil(extract(epoch FROM v_lock))::int);
  END IF;

  -- Within the cap → record and allow.
  INSERT INTO public.email_otp_throttle (email, attempts, window_start, blocked_until, updated_at)
  VALUES (v_email, v_attempts, v_start, NULL, v_now)
  ON CONFLICT (email) DO UPDATE
    SET attempts = EXCLUDED.attempts,
        window_start = EXCLUDED.window_start,
        blocked_until = NULL,
        updated_at = v_now;

  RETURN jsonb_build_object('allowed', true, 'remaining', v_max - v_attempts);
END;
$$;

REVOKE ALL ON FUNCTION public.register_otp_resend(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_otp_resend(TEXT) TO anon, authenticated;
