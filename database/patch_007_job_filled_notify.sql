-- =====================================================================
--  PATCH 007 — Notification: job marked as filled
--
--  WHY:  Part 23 lists "Job marked as filled → poster (success message)"
--        as a required trigger. patch_006 covered every fan-out gap
--        except the job-filled one (it depends on app code that ships
--        in this same session: JobService.markAsFilled() + a button on
--        the poster's job_details_screen).
--
--  WHAT: One trigger on public.jobs UPDATE OF status. When the row
--        transitions INTO 'filled', drop a success row in
--        public.notifications for poster_id. The existing
--        notifications → notify-fcm webhook pushes it to the device.
--
--  PREREQUISITES: schema.sql + patch_001..patch_006 already applied.
--  IDEMPOTENT:    yes — DROP TRIGGER IF EXISTS + CREATE OR REPLACE.
-- =====================================================================


CREATE OR REPLACE FUNCTION public.notify_job_filled()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status <> 'filled' THEN RETURN NEW; END IF;
  IF OLD.status = 'filled' THEN RETURN NEW; END IF;
  IF NEW.poster_id IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    NEW.poster_id,
    'Position filled',
    'Nice work — "' || COALESCE(NEW.title, 'your job post') ||
      '" is marked as filled and hidden from new applicants.',
    'job_filled',
    NEW.id::text,
    'job'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_job_filled ON public.jobs;
CREATE TRIGGER trg_notify_job_filled
  AFTER UPDATE OF status ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.notify_job_filled();


-- =====================================================================
--  END OF PATCH 007
-- =====================================================================
