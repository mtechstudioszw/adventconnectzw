-- =====================================================================
--  PATCH 302 — the 5-day job expiry reminder never ran
--  STATUS: APPLIED 2 Nov 2026 (by Claude via the Supabase connector,
--  verified: the cron job's function runs and returns 0 — no jobs today)
--
--  cron "jobs_expiry_reminder_5d" failed every morning since it was
--  scheduled: enqueue_job_expiry_reminders() filtered on jobs.is_active,
--  a column the jobs redesign (patch_278) does not have. A live job is
--  status = 'open' (pending/open/filled/closed/expired). The 3-day
--  warning (enqueue_job_expiry_warnings) was unaffected.
--
--  CLAUDE.md checklist: no profiles change; no triggers.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.enqueue_job_expiry_reminders()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_count INTEGER := 0;
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT j.id, j.poster_id, j.title
      FROM public.jobs j
     WHERE j.expires_at > NOW() + INTERVAL '4 days'
       AND j.expires_at <= NOW() + INTERVAL '5 days'
       AND j.status = 'open'
       AND j.poster_id IS NOT NULL
       AND j.expiry_reminded_at IS NULL
  LOOP
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    ) VALUES (
      v_row.poster_id,
      'Job expires in 5 days',
      '"' || v_row.title || '" will be removed from the marketplace in 5 days. Renew it from your job listing to keep it visible.',
      'job_expiry_reminder',
      v_row.id::text,
      'job'
    );
    UPDATE public.jobs SET expiry_reminded_at = NOW() WHERE id = v_row.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;
