-- =====================================================================
--  PATCH 107 — age (date_of_birth) edit rules
--
--  Users may edit their age, but:
--    * must be at least 16 years old, and
--    * can only change it once every 3 months.
--  Enforced server-side (BEFORE UPDATE on profiles) so the client can't
--  bypass it. date_of_birth_changed_at is the per-user clock, and is
--  pinned to its old value when DOB doesn't change (can't be hand-edited).
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS date_of_birth_changed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.enforce_dob_rules()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.date_of_birth IS DISTINCT FROM OLD.date_of_birth THEN
    -- Minimum age 16.
    IF NEW.date_of_birth IS NOT NULL
       AND NEW.date_of_birth > (CURRENT_DATE - INTERVAL '16 years') THEN
      RAISE EXCEPTION 'You must be at least 16 years old.';
    END IF;
    -- One change per 3 months.
    IF OLD.date_of_birth_changed_at IS NOT NULL
       AND OLD.date_of_birth_changed_at > (now() - INTERVAL '3 months') THEN
      RAISE EXCEPTION 'You can only change your age once every 3 months.';
    END IF;
    NEW.date_of_birth_changed_at := now();
  ELSE
    -- DOB unchanged → freeze the clock (no hand-editing it).
    NEW.date_of_birth_changed_at := OLD.date_of_birth_changed_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_dob_rules ON public.profiles;
CREATE TRIGGER trg_enforce_dob_rules
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_dob_rules();
