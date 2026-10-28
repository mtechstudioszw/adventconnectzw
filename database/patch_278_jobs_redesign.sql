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

COMMIT;

-- Checks (as an ordinary member):
--   * Post a job from the API with status 'open' → it lands 'pending'.
--   * PATCH a rejected job to 'open' → stays rejected.
--   * Change the phone number on a live job → back to 'pending'.
--   * Mark as filled / Reopen / Renew → work as before.
--   * Super admin approve / reject → work as before.
