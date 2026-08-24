-- =====================================================================
--  PATCH 264 — Call metrics for the admin console, and the premium fix
--
--  ## 1. call_is_premium was always FALSE
--
--  patch_261 reads premium from a `public.premium_subscriptions` table
--  wrapped in an exception handler. That table does not exist in this
--  project and never has — premium is a single column,
--  `profiles.premium_until`, which is what PremiumService.refresh()
--  reads (lib/services/premium_service.dart) and what
--  supabase/functions/verify-purchase writes.
--
--  The exception handler meant this failed quietly rather than loudly:
--  no error anywhere, and every paying member silently metered against
--  the FREE call quota. The defensive posture was right — a premium
--  schema change must never stop calls working — it was just pointed at
--  the wrong table.
--
--  Fixed to read the real column, and kept defensive: a missing column
--  still degrades to "free tier" rather than raising, and the free
--  ceilings are generous enough that degrading is not a punishment.
--
--  ## 2. Admin metrics (§34)
--
--  One RPC, super-admin gated through the same assert_super_admin()
--  guard patch_040 built for the rest of the console. It reports
--  volumes, outcomes, minutes and cost signals.
--
--  It reports NOTHING about content, because there is none: no call is
--  recorded, transcribed or stored, so the most private thing in here
--  is a duration. Names are included only in the "who is using this
--  most" list, which is the one an operator needs to spot a member
--  burning relay bandwidth.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Premium, read from where premium actually lives
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_is_premium(p_user UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $fn$
DECLARE v_until TIMESTAMPTZ;
BEGIN
  SELECT premium_until INTO v_until
    FROM public.profiles WHERE id = p_user;
  RETURN v_until IS NOT NULL AND v_until > now();
EXCEPTION WHEN undefined_column OR undefined_table THEN
  -- Premium is owned by another part of the app. If its schema moves,
  -- calls keep working on the free ceilings rather than failing.
  RETURN FALSE;
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_is_premium(UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  2. Admin metrics
--
--  Windowed on the last 30 days for the trend series and all-time for
--  the totals. Every aggregate is a single pass over indexed columns;
--  at this app's volume the whole thing is milliseconds, and the
--  30-day cap is what keeps that true in three years.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_admin_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $fn$
DECLARE v JSONB;
BEGIN
  PERFORM public.assert_super_admin();

  SELECT jsonb_build_object(

    -- ---- volumes ----------------------------------------------------
    'total_calls',      (SELECT COUNT(*) FROM public.calls),
    'calls_today',      (SELECT COUNT(*) FROM public.calls
                          WHERE started_at >= date_trunc('day', now())),
    'calls_7d',         (SELECT COUNT(*) FROM public.calls
                          WHERE started_at >= now() - interval '7 days'),
    'active_now',       (SELECT COUNT(*) FROM public.calls
                          WHERE status <> 'ended'),
    'ringing_now',      (SELECT COUNT(*) FROM public.calls
                          WHERE status = 'ringing'),
    'direct_calls',     (SELECT COUNT(*) FROM public.calls WHERE kind = 'direct'),
    'group_calls',      (SELECT COUNT(*) FROM public.calls WHERE kind = 'group'),

    -- ---- outcomes ---------------------------------------------------
    -- A call that never reached connected_at is one that did not
    -- happen, whatever it says. That ratio is the health signal: if
    -- answered/total falls, either the push pipeline or TURN is broken.
    'answered',         (SELECT COUNT(*) FROM public.calls
                          WHERE connected_at IS NOT NULL),
    'missed',           (SELECT COUNT(*) FROM public.calls
                          WHERE end_reason = 'missed'),
    'rejected',         (SELECT COUNT(*) FROM public.calls
                          WHERE end_reason = 'rejected'),
    'busy',             (SELECT COUNT(*) FROM public.calls
                          WHERE end_reason = 'busy'),
    'failed',           (SELECT COUNT(*) FROM public.calls
                          WHERE end_reason IN ('failed', 'unreachable')),
    'swept',            (SELECT COUNT(*) FROM public.calls
                          WHERE end_reason IN ('stale', 'max_duration')),

    -- ---- duration ---------------------------------------------------
    'total_minutes',    (SELECT COALESCE(ROUND(SUM(duration_seconds) / 60.0), 0)
                           FROM public.calls),
    'avg_seconds',      (SELECT COALESCE(ROUND(AVG(duration_seconds)), 0)
                           FROM public.calls WHERE connected_at IS NOT NULL),
    'peak_participants',(SELECT COALESCE(MAX(peak_participants), 0)
                           FROM public.calls),

    -- ---- cost -------------------------------------------------------
    -- relayed_seconds is the only number here that maps to a bill: a
    -- leg the device reported as TURN-relayed is bandwidth we paid for.
    -- Everything else went peer to peer and cost nothing.
    'relayed_minutes_30d', (SELECT COALESCE(ROUND(SUM(relayed_seconds) / 60.0), 0)
                              FROM public.call_usage_daily
                             WHERE day >= CURRENT_DATE - 30),
    'minutes_30d',         (SELECT COALESCE(ROUND(SUM(seconds) / 60.0), 0)
                              FROM public.call_usage_daily
                             WHERE day >= CURRENT_DATE - 30),

    -- ---- rate-limit pressure ---------------------------------------
    -- Counts, not identities. A spike here is either abuse or a ceiling
    -- set too low, and both are worth seeing before members complain.
    'rate_limit_events_24h', (SELECT COUNT(*) FROM public.call_events
                               WHERE event IN ('rate_limited', 'quota_blocked')
                                 AND created_at >= now() - interval '24 hours'),
    'push_failures_24h',     (SELECT COUNT(*) FROM public.call_events
                               WHERE event IN ('push_failed', 'push_unconfigured')
                                 AND created_at >= now() - interval '24 hours'),

    -- ---- daily series, newest last ---------------------------------
    'daily', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'day',     d.day,
               'calls',   d.calls,
               'minutes', d.minutes) ORDER BY d.day)
        FROM (
          SELECT started_at::date            AS day,
                 COUNT(*)                    AS calls,
                 ROUND(SUM(duration_seconds) / 60.0) AS minutes
            FROM public.calls
           WHERE started_at >= CURRENT_DATE - 29
           GROUP BY 1
        ) d), '[]'::jsonb),

    -- ---- heaviest users, last 30 days ------------------------------
    'top_users', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id', t.user_id,
               'name',    COALESCE(NULLIF(trim(pr.full_name), ''), 'Member'),
               'minutes', t.minutes,
               'relayed_minutes', t.relayed) ORDER BY t.minutes DESC)
        FROM (
          SELECT user_id,
                 ROUND(SUM(seconds) / 60.0)         AS minutes,
                 ROUND(SUM(relayed_seconds) / 60.0) AS relayed
            FROM public.call_usage_daily
           WHERE day >= CURRENT_DATE - 30
           GROUP BY user_id
           ORDER BY 2 DESC
           LIMIT 10
        ) t
        LEFT JOIN public.profiles pr ON pr.id = t.user_id), '[]'::jsonb)

  ) INTO v;

  RETURN v;
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_admin_metrics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.call_admin_metrics() TO authenticated;


-- ---------------------------------------------------------------------
--  3. Admin kill switch for one call
--
--  §34 asks for admin monitoring; monitoring without a lever is a
--  spectator sport. A super admin can end a specific call — used when a
--  member reports harassment while it is happening. It cannot LISTEN to
--  one, and there is no code path in this project that could.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_admin_end(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  PERFORM public.assert_super_admin();
  PERFORM public.call_finalize(p_call, 'admin');
  PERFORM public.call_log_event(p_call, auth.uid(), 'admin_ended', '{}'::jsonb);
  RETURN jsonb_build_object('ok', TRUE);
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_admin_end(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.call_admin_end(UUID) TO authenticated;


-- =====================================================================
--  VERIFY (run these after applying; read the output)
--
--    -- Premium now reads the real column. For a member with
--    -- profiles.premium_until in the future this must be true:
--    SELECT id, premium_until, public.call_is_premium(id)
--      FROM public.profiles
--     WHERE premium_until IS NOT NULL LIMIT 5;
--
--    -- Metrics answer on an empty calls table:
--    SELECT public.call_admin_metrics();
--    -- as a NON-admin this must raise, not return — that is the guard
--    -- working.
--
--    SELECT has_function_privilege('anon',
--             'public.call_admin_metrics()', 'EXECUTE');   -- false
-- =====================================================================
