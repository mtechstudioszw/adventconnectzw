-- =====================================================================
--  PATCH 299 — keep the re-send tables small
--  STATUS: APPLIED 2 Nov 2026 (by the owner, verified by Claude)
--
--  patch_298's request/copy tables only matter until the reader's phone
--  has picked a copy up. Copies older than 30 days and fulfilled
--  requests older than 7 days are pruned nightly, inside the existing
--  prune-operational-logs job (restated in full from patch_292).
--
--  CLAUDE.md checklist: no profiles change; no triggers.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'cron'
AS $function$
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';
  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';
  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';
  DELETE FROM public.call_events WHERE created_at < now() - interval '30 days';
  DELETE FROM supabase_functions.hooks WHERE created_at < now() - interval '2 days';

  DELETE FROM public.e2ee_prekeys k
   USING (
     SELECT user_id, device_id, key_id,
            row_number() OVER (PARTITION BY user_id, device_id
                               ORDER BY created_at DESC, key_id DESC) AS rn
       FROM public.e2ee_prekeys
      WHERE claimed_at IS NULL
   ) x
   WHERE x.rn > 100
     AND k.user_id = x.user_id AND k.device_id = x.device_id
     AND k.key_id = x.key_id AND k.claimed_at IS NULL;
  DELETE FROM public.e2ee_prekeys
   WHERE claimed_at IS NOT NULL AND claimed_at < now() - interval '30 days';

  -- patch 299: re-send copies and requests (patch_298).
  DELETE FROM public.e2ee_message_copies
   WHERE created_at < now() - interval '30 days';
  DELETE FROM public.e2ee_resend_requests
   WHERE (fulfilled_at IS NOT NULL AND fulfilled_at < now() - interval '7 days')
      OR created_at < now() - interval '30 days';

  DELETE FROM public.app_events   WHERE created_at < now() - interval '120 days';
  DELETE FROM public.app_sessions WHERE started_at < now() - interval '120 days';

  BEGIN
    DELETE FROM auth.refresh_tokens
     WHERE revoked AND updated_at < now() - interval '7 days';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'refresh_tokens prune skipped: no privilege';
  END;
END;
$function$;

COMMIT;
