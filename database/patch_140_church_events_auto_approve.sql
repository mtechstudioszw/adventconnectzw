-- patch_140: church-posted events skip the approval queue.
-- An event tagged with a church (church_id) and posted by that church's
-- APPROVED admin goes live immediately (status='approved'), same as a super
-- admin's own events. Community events from regular members still default to
-- 'pending' and need super-admin review.

CREATE OR REPLACE FUNCTION public.events_auto_approve()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Super admin's own events: auto-approve.
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE id = NEW.organizer_id AND is_super_admin = TRUE) THEN
    NEW.status := 'approved';
  -- Church events posted by that church's approved admin: auto-approve.
  ELSIF NEW.church_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.church_admins ca
     WHERE ca.church_id = NEW.church_id
       AND ca.user_id = NEW.organizer_id
       AND ca.status = 'approved'
  ) THEN
    NEW.status := 'approved';
  END IF;
  RETURN NEW;
END;
$function$;
