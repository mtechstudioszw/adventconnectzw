-- ============================================================================
--  patch_278 — Jobs: moderation guard, apply details, company Pages, saved
--  STATUS: DRAFT, NOT YET RUN. Run AFTER 275 (company Pages) and 276.
-- ============================================================================
--
--  1. SECURITY. `authenticated` may update every column of its own jobs
--     and the only check is "it's your row", so a poster could:
--       * insert a job already 'open', skipping review (jobs default to
--         'pending' since patch_109, but the client can send a status);
--       * flip 'pending' or 'rejected' to 'open' — publish what the
--         moderators refused;
--       * push expires_at years ahead.
--     The guard lets the real paths through and nothing else:
--       * super admins + server work (admin_approve_job / admin_reject_job
--         run as the admin);
--       * poster: open ⇄ filled, open → closed (the app's Mark as filled /
--         Reopen), and renew_job's expired → open with a fresh 30 days;
--       * editing the scam-relevant fields of a LIVE job (title, employer,
--         contact phone/email, apply link, salary, linked Page) sends it
--         back to 'pending' for another look — an approved listing can't
--         be quietly turned into a different one.
--
--  2. New listing fields the redesigned form collects:
--       work_arrangement  on_site | remote | hybrid
--       apply_instructions  free text ("Send CV and two references…")
--       apply_url  http(s) link to an application form
--       page_id  the employer's organization Page (patch_275) — the
--                company profile. Only an admin of that Page can link it;
--                the Page's own verification is what shows as verified.
--
--  3. saved_jobs — each member's private list.
--
--  4. Jobs for every kind of work (owner, 28 Oct 2026: "garden boys, house
--     girls … medical … professional — it should accommodate everyone"):
--       job_type 'casual' (day / piece work); three new fields
--       (cleaning_security, hospitality_retail, creative_media);
--       structured pay — pay_min, pay_max, pay_period (hour/day/week/
--       month/year/job), pay_currency — so "$15 a day" reads as such;
--       is_urgent ("Start now").
--
--  5. BUG: renew_job set status = 'active' on an expired job. 'active'
--     isn't an allowed status (jobs_status_check), so renewing an expired
--     job has ALWAYS failed. It now sets 'open'.
--
--  6. job_applications — Quick apply inside the app. The applicant sends
--     a short message + phone; the poster is notified (push), sees an
--     Applicants list and can shortlist (applicant notified) or decline.
--     Posters only ever see applications to their own jobs; applicants
--     only their own. Max 30 applications a day per member.
--     job_applicant_count() — the real number, for "5 people applied".
--
--  7. job_alerts — "tell me when a nurse job is posted in Zimbabwe". When a
--     moderator approves a matching vacancy, each subscriber gets one
--     notification (push via the existing notifications trigger; Sabbath
--     suppression applies as for everything else). Max 10 alerts each.
--
--  CLAUDE.md: BEFORE triggers return COALESCE(NEW, OLD).
-- ============================================================================

BEGIN;

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS work_arrangement text,
  ADD COLUMN IF NOT EXISTS apply_instructions text,
  ADD COLUMN IF NOT EXISTS apply_url text,
  ADD COLUMN IF NOT EXISTS page_id uuid REFERENCES public.pages(id) ON DELETE SET NULL;

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_work_arrangement_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_work_arrangement_check
  CHECK (work_arrangement IS NULL OR work_arrangement IN ('on_site', 'remote', 'hybrid'));
ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_apply_url_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_apply_url_check
  CHECK (apply_url IS NULL OR (length(apply_url) <= 300 AND apply_url ~* '^https?://[^\s]+$'));
ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_apply_instructions_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_apply_instructions_check
  CHECK (apply_instructions IS NULL OR length(apply_instructions) <= 1000);

-- 4. Every kind of work -------------------------------------------------------
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS pay_min numeric(12,2),
  ADD COLUMN IF NOT EXISTS pay_max numeric(12,2),
  ADD COLUMN IF NOT EXISTS pay_period text,
  ADD COLUMN IF NOT EXISTS pay_currency text,
  ADD COLUMN IF NOT EXISTS is_urgent boolean NOT NULL DEFAULT false;

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_pay_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_pay_check CHECK (
      (pay_min IS NULL OR pay_min >= 0)
  AND (pay_max IS NULL OR pay_max >= 0)
  AND (pay_min IS NULL OR pay_max IS NULL OR pay_max >= pay_min)
  AND (pay_period IS NULL OR pay_period IN ('hour','day','week','month','year','job'))
  AND (pay_currency IS NULL OR pay_currency ~ '^[A-Z]{3}$'));

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_job_type_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_job_type_check CHECK (job_type = ANY (ARRAY[
  'full_time','part_time','contract','casual','internship','volunteer']));

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_category_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_category_check CHECK (category = ANY (ARRAY[
  'teaching_education','healthcare','construction_trades','farming_agriculture',
  'driving_transport','domestic_caregiving','business_admin','it_technology',
  'ministry_church','cleaning_security','hospitality_retail','creative_media',
  'other']));

CREATE INDEX IF NOT EXISTS jobs_open_feed
  ON public.jobs (country, created_at DESC) WHERE status = 'open';

CREATE INDEX IF NOT EXISTS jobs_page ON public.jobs (page_id) WHERE page_id IS NOT NULL;

-- 1. Guard -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.jobs_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_ok boolean;
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Linking a company Page needs to be one of its admins.
  IF NEW.page_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.page_id IS DISTINCT FROM OLD.page_id)
     AND NOT public.can_edit_page(NEW.page_id) THEN
    RAISE EXCEPTION 'Only an admin of that Page can post jobs for it.'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.expires_at := now() + interval '30 days';
    NEW.poster_id := auth.uid();
    RETURN COALESCE(NEW, OLD);
  END IF;

  NEW.poster_id := OLD.poster_id;
  NEW.created_at := OLD.created_at;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_ok := (OLD.status = 'open'   AND NEW.status IN ('filled', 'closed'))
         OR (OLD.status = 'filled' AND NEW.status = 'open')
         -- renew_job: expired → open with a fresh 30 days
         OR (OLD.status = 'expired' AND NEW.status = 'open'
             AND NEW.expires_at BETWEEN now() + interval '29 days'
                                    AND now() + interval '31 days');
    IF NOT v_ok THEN
      NEW.status := OLD.status;
    END IF;
  END IF;

  -- Expiry only moves by renewing (a fresh 30 days), never further.
  IF NEW.expires_at IS DISTINCT FROM OLD.expires_at
     AND NOT (NEW.expires_at BETWEEN now() + interval '29 days'
                                 AND now() + interval '31 days') THEN
    NEW.expires_at := OLD.expires_at;
  END IF;

  -- A live listing whose identity changes goes back for review.
  IF OLD.status = 'open' AND NEW.status = 'open' AND (
       NEW.title IS DISTINCT FROM OLD.title
    OR NEW.company IS DISTINCT FROM OLD.company
    OR NEW.contact_phone IS DISTINCT FROM OLD.contact_phone
    OR NEW.contact_email IS DISTINCT FROM OLD.contact_email
    OR NEW.apply_url IS DISTINCT FROM OLD.apply_url
    OR NEW.salary_range IS DISTINCT FROM OLD.salary_range
    OR NEW.pay_min IS DISTINCT FROM OLD.pay_min
    OR NEW.pay_max IS DISTINCT FROM OLD.pay_max
    OR NEW.page_id IS DISTINCT FROM OLD.page_id) THEN
    NEW.status := 'pending';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS jobs_guard_trg ON public.jobs;
-- Order with trg_jobs_auto_approve doesn't matter: the guard skips super
-- admins entirely, so their own posts are still auto-approved.
CREATE TRIGGER jobs_guard_trg BEFORE INSERT OR UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.jobs_guard();

-- 3. Saved jobs ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.saved_jobs (
  user_id    uuid   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  job_id     bigint NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, job_id)
);
ALTER TABLE public.saved_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS saved_jobs_own ON public.saved_jobs;
CREATE POLICY saved_jobs_own ON public.saved_jobs FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
REVOKE ALL ON public.saved_jobs FROM anon;
GRANT SELECT, INSERT, DELETE ON public.saved_jobs TO authenticated;

-- 5. renew_job: 'open', not the non-existent 'active' ------------------------
CREATE OR REPLACE FUNCTION public.renew_job(p_job_id bigint)
RETURNS public.jobs LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_row public.jobs;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to renew a job.';
  END IF;

  UPDATE public.jobs
     SET expires_at          = NOW() + INTERVAL '30 days',
         expiry_reminded_at  = NULL,
         status              = CASE WHEN status = 'expired' THEN 'open'
                                    ELSE status END
   WHERE id = p_job_id
     AND poster_id = v_caller
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Job % not found or not yours.', p_job_id;
  END IF;

  RETURN v_row;
END;
$function$;

-- 6. Applications ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_applications (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id       bigint NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  applicant_id uuid   NOT NULL DEFAULT auth.uid()
                      REFERENCES public.profiles(id) ON DELETE CASCADE,
  message      text CHECK (message IS NULL OR length(message) <= 1000),
  phone        text CHECK (phone IS NULL OR length(phone) <= 30),
  status       text NOT NULL DEFAULT 'sent'
               CHECK (status IN ('sent','viewed','shortlisted','declined')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, applicant_id)
);
CREATE INDEX IF NOT EXISTS job_applications_applicant
  ON public.job_applications (applicant_id, created_at DESC);

ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS job_applications_read ON public.job_applications;
CREATE POLICY job_applications_read ON public.job_applications FOR SELECT
  USING (applicant_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.jobs j
                     WHERE j.id = job_id AND j.poster_id = auth.uid()));

DROP POLICY IF EXISTS job_applications_apply ON public.job_applications;
CREATE POLICY job_applications_apply ON public.job_applications FOR INSERT
  WITH CHECK (applicant_id = auth.uid()
              AND public.user_is_active()
              AND EXISTS (SELECT 1 FROM public.jobs j
                           WHERE j.id = job_id
                             AND j.status = 'open'
                             AND j.post_type = 'hiring'
                             AND j.expires_at > now()
                             AND j.poster_id <> auth.uid()));

-- Only the job's poster moves the status (column grant limits it to
-- status); the applicant withdraws by deleting.
DROP POLICY IF EXISTS job_applications_review ON public.job_applications;
CREATE POLICY job_applications_review ON public.job_applications FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.jobs j
                  WHERE j.id = job_id AND j.poster_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.jobs j
                       WHERE j.id = job_id AND j.poster_id = auth.uid()));

DROP POLICY IF EXISTS job_applications_withdraw ON public.job_applications;
CREATE POLICY job_applications_withdraw ON public.job_applications FOR DELETE
  USING (applicant_id = auth.uid());

REVOKE ALL ON public.job_applications FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.job_applications TO authenticated;
GRANT UPDATE (status) ON public.job_applications TO authenticated;

CREATE OR REPLACE FUNCTION public.job_applications_before()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'sent';
    NEW.created_at := now();
    IF auth.uid() IS NOT NULL AND (
         SELECT count(*) FROM public.job_applications
          WHERE applicant_id = auth.uid()
            AND created_at > now() - interval '1 day') >= 30 THEN
      RAISE EXCEPTION 'You have sent 30 applications today. Try again tomorrow.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS job_applications_before_trg ON public.job_applications;
CREATE TRIGGER job_applications_before_trg
  BEFORE INSERT OR UPDATE ON public.job_applications
  FOR EACH ROW EXECUTE FUNCTION public.job_applications_before();

CREATE OR REPLACE FUNCTION public.job_applications_notify()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_job public.jobs;
  v_name text;
BEGIN
  SELECT * INTO v_job FROM public.jobs WHERE id = NEW.job_id;
  IF v_job.id IS NULL THEN RETURN NULL; END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT COALESCE(NULLIF(full_name, ''), 'A member') INTO v_name
      FROM public.profiles WHERE id = NEW.applicant_id;
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    VALUES (v_job.poster_id, 'New applicant',
            COALESCE(v_name, 'A member') || ' applied for "' || v_job.title || '".',
            'job_application', v_job.id::text, 'job');
  ELSIF NEW.status = 'shortlisted' AND OLD.status IS DISTINCT FROM 'shortlisted' THEN
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    VALUES (NEW.applicant_id, 'You''re shortlisted',
            'For "' || v_job.title || '". The employer may contact you soon.',
            'job_application_update', v_job.id::text, 'job');
  END IF;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS job_applications_notify_trg ON public.job_applications;
CREATE TRIGGER job_applications_notify_trg
  AFTER INSERT OR UPDATE OF status ON public.job_applications
  FOR EACH ROW EXECUTE FUNCTION public.job_applications_notify();

-- The real count, for "5 people applied" on a public job.
CREATE OR REPLACE FUNCTION public.job_applicant_count(p_job_id bigint)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.job_applications a
    JOIN public.jobs j ON j.id = a.job_id
   WHERE a.job_id = p_job_id
     AND (j.status IN ('open','filled','closed') OR j.poster_id = auth.uid());
$function$;
REVOKE ALL ON FUNCTION public.job_applicant_count(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.job_applicant_count(bigint) TO anon, authenticated;

-- 7. Alerts -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_alerts (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    uuid NOT NULL DEFAULT auth.uid()
             REFERENCES public.profiles(id) ON DELETE CASCADE,
  category   text,
  job_type   text,
  country    text,
  keyword    text CHECK (keyword IS NULL OR length(keyword) <= 60),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS job_alerts_user ON public.job_alerts (user_id);
ALTER TABLE public.job_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS job_alerts_own ON public.job_alerts;
CREATE POLICY job_alerts_own ON public.job_alerts FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
REVOKE ALL ON public.job_alerts FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.job_alerts TO authenticated;

CREATE OR REPLACE FUNCTION public.job_alerts_limit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF (SELECT count(*) FROM public.job_alerts WHERE user_id = NEW.user_id) >= 10 THEN
    RAISE EXCEPTION 'You can have up to 10 job alerts.' USING ERRCODE = 'P0001';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;
DROP TRIGGER IF EXISTS job_alerts_limit_trg ON public.job_alerts;
CREATE TRIGGER job_alerts_limit_trg BEFORE INSERT ON public.job_alerts
  FOR EACH ROW EXECUTE FUNCTION public.job_alerts_limit();

-- Fires when a vacancy goes live: moderator approval (pending → open) or a
-- super admin's own post (inserted open). One notification per member per
-- job, ever — re-approving an edited job doesn't notify twice.
CREATE OR REPLACE FUNCTION public.jobs_notify_alerts()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_where text;
BEGIN
  IF NEW.status <> 'open' OR NEW.post_type <> 'hiring' THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status <> 'pending' THEN RETURN NULL; END IF;
  IF NEW.expires_at IS NOT NULL AND NEW.expires_at <= now() THEN RETURN NULL; END IF;

  v_where := concat_ws(' · ', NULLIF(NEW.company, ''), NULLIF(NEW.location, ''));

  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  SELECT DISTINCT a.user_id,
         'New job: ' || NEW.title,
         COALESCE(NULLIF(v_where, ''), 'Matches your job alert'),
         'job_alert', NEW.id::text, 'job'
    FROM public.job_alerts a
   WHERE a.user_id <> NEW.poster_id
     AND (a.category IS NULL OR a.category = NEW.category)
     AND (a.job_type IS NULL OR a.job_type = NEW.job_type)
     AND (a.country  IS NULL OR a.country  = NEW.country)
     AND (a.keyword  IS NULL
          OR NEW.title ILIKE '%' || a.keyword || '%'
          OR NEW.description ILIKE '%' || a.keyword || '%')
     AND NOT EXISTS (SELECT 1 FROM public.notifications n
                      WHERE n.user_id = a.user_id
                        AND n.type = 'job_alert'
                        AND n.reference_id = NEW.id::text);
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS jobs_notify_alerts_trg ON public.jobs;
CREATE TRIGGER jobs_notify_alerts_trg
  AFTER INSERT OR UPDATE OF status ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.jobs_notify_alerts();

COMMIT;

-- Checks (as an ordinary member):
--   * Post a job from the API with status 'open' → it lands 'pending'.
--   * PATCH a rejected job to 'open' → stays rejected.
--   * Change the phone number on a live job → back to 'pending'.
--   * Mark as filled / Reopen / Renew → work as before.
--   * Super admin approve / reject → work as before.
--   * Renew an EXPIRED job → it comes back 'open' (used to error).
--   * Apply to someone else's open vacancy → poster gets "New applicant";
--     apply to your own / a pending job → refused.
--   * Poster shortlists → applicant gets "You're shortlisted".
--   * Create an alert (category healthcare, country ZW), approve a
--     matching job as admin → one "New job: …" notification.
