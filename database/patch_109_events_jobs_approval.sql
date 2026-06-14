-- =====================================================================
--  PATCH 109 — Events + Jobs require admin approval before going live
--
--  Events already have the visibility RLS (non-admins see only
--  status='approved' + their own). We just default new events to
--  'pending'. Jobs use status as a lifecycle (open/filled/closed/expired
--  are visible); we add 'pending'/'rejected' and default new jobs to
--  'pending' so they're hidden until approved (→ 'open'). The super
--  admin's own posts auto-approve so they never wait on themselves.
-- =====================================================================

-- ---------- EVENTS ----------------------------------------------------
ALTER TABLE public.events ALTER COLUMN status SET DEFAULT 'pending';

CREATE OR REPLACE FUNCTION public.events_auto_approve()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE id = NEW.organizer_id AND is_super_admin = TRUE) THEN
    NEW.status := 'approved';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_events_auto_approve ON public.events;
CREATE TRIGGER trg_events_auto_approve BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.events_auto_approve();

-- ---------- JOBS ------------------------------------------------------
ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_status_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_status_check
  CHECK (status = ANY (ARRAY['pending','open','closed','filled','expired','rejected']));
ALTER TABLE public.jobs ALTER COLUMN status SET DEFAULT 'pending';

CREATE OR REPLACE FUNCTION public.jobs_auto_approve()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE id = NEW.poster_id AND is_super_admin = TRUE) THEN
    NEW.status := 'open';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_jobs_auto_approve ON public.jobs;
CREATE TRIGGER trg_jobs_auto_approve BEFORE INSERT ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.jobs_auto_approve();

-- ---------- ADMIN QUEUE RPCs (super-admin only) -----------------------
CREATE OR REPLACE FUNCTION public.admin_list_pending_events()
RETURNS SETOF public.events LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY SELECT * FROM public.events
    WHERE status = 'pending' ORDER BY created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_approve_event(p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_org UUID; v_title TEXT;
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.events SET status = 'approved' WHERE id = p_id
    RETURNING organizer_id, title INTO v_org, v_title;
  IF v_org IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
    VALUES (v_org, 'Event approved', 'Your event "' || COALESCE(v_title,'') || '" is now live.',
            'event', p_id::text, 'event');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_event(p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.events SET status = 'rejected' WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_pending_jobs()
RETURNS SETOF public.jobs LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY SELECT * FROM public.jobs
    WHERE status = 'pending' ORDER BY created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_approve_job(p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_poster UUID; v_title TEXT;
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.jobs SET status = 'open' WHERE id = p_id
    RETURNING poster_id, title INTO v_poster, v_title;
  IF v_poster IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
    VALUES (v_poster, 'Job approved', 'Your job "' || COALESCE(v_title,'') || '" is now live.',
            'job', p_id::text, 'job');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_job(p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.jobs SET status = 'rejected' WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_pending_events(), public.admin_approve_event(BIGINT),
  public.admin_reject_event(BIGINT), public.admin_list_pending_jobs(),
  public.admin_approve_job(BIGINT), public.admin_reject_job(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_pending_events(), public.admin_approve_event(BIGINT),
  public.admin_reject_event(BIGINT), public.admin_list_pending_jobs(),
  public.admin_approve_job(BIGINT), public.admin_reject_job(BIGINT) TO authenticated;
