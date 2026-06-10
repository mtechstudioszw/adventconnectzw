-- =====================================================================
--  PATCH 069 — Home-church change cooldown (one self-change / 90 days)
--
--  Founder decision: a user may change their home church themselves, but
--  only once every 90 days (anti group-hopping). Enforced by a BEFORE
--  UPDATE trigger so it holds no matter which code path writes church_id.
--  First-ever set (OLD.church_id NULL) is always allowed and stamps the
--  clock. Church-group membership is implicit (profiles.church_id), so
--  changing church automatically moves the user between church groups.
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS church_changed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.enforce_church_change_cooldown()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.church_id IS DISTINCT FROM OLD.church_id THEN
    -- Cooldown check uses the STORED (OLD) clock — a client can't pass a
    -- forged NEW.church_changed_at to slip past it.
    IF OLD.church_id IS NOT NULL
       AND OLD.church_changed_at IS NOT NULL
       AND OLD.church_changed_at > now() - INTERVAL '90 days' THEN
      RAISE EXCEPTION 'You can only change your home church once every 90 days. Next change available after %.',
        to_char(OLD.church_changed_at + INTERVAL '90 days', 'Mon DD, YYYY');
    END IF;
    NEW.church_changed_at := now();   -- trigger sets it, not the client
  ELSE
    -- church_id unchanged: forbid hand-editing the cooldown clock (the
    -- bypass where you reset church_changed_at to the past, THEN switch
    -- church). Force it back to the stored value.
    NEW.church_changed_at := OLD.church_changed_at;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_church_change_cooldown ON public.profiles;
CREATE TRIGGER trg_church_change_cooldown
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_church_change_cooldown();
