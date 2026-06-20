-- =====================================================================
--  PATCH 120 — claim church REALLY fixed.
--
--  church_admins_pin_pending_on_insert() forced NEW.role := 'member' on
--  every insert. But church_admins_role_check only allows 'primary' /
--  'standard', so EVERY claim hit check constraint 23514 — regardless of
--  what the app sent (the app-side role='primary' fix was silently
--  overwritten by this trigger). Set a VALID role instead.
--
--  Security intent of the trigger is preserved: a user's claim is always
--  pinned to status='pending' (they can't self-approve); we just store a
--  role the constraint accepts. 'primary' = "applying to be this church's
--  main admin"; the super-admin can downgrade to 'standard' on approval.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.church_admins_pin_pending_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  -- Anything a user posts is a pending application, full stop.
  NEW.status := 'pending';
  -- Must be a value church_admins_role_check accepts ('primary'/'standard').
  -- 'member' violated the constraint and broke every claim.
  NEW.role := 'primary';
  RETURN NEW;
END;
$function$;
