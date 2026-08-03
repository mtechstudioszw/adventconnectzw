-- patch_185 (#16): tell the church's primary admin how their nomination went.
--
-- `notify_church_admin_status` inserted exactly one notification, to
-- `NEW.user_id` — the nominee. So when a super admin approved or rejected
-- someone, the primary admin who put that person forward was told nothing
-- at all. From their side the nomination simply sat on "pending" forever,
-- and the only way to discover otherwise was to reopen the admin list and
-- read the status column.
--
-- Rejection is the case that actually hurts: the primary admin is the one
-- who has to go back to that member and explain, and they never learned
-- there was anything to explain.
--
-- Only super-admin DECISIONS notify the primary. The 'pending' insert does
-- not: that transition is the primary admin's own nomination, and telling
-- someone what they just did is noise.

CREATE OR REPLACE FUNCTION public.notify_church_admin_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  cname     TEXT;
  who       TEXT;
  primary_id UUID;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  SELECT name INTO cname FROM public.churches WHERE id = NEW.church_id;

  -- 1. The nominee. Unchanged.
  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    NEW.user_id,
    CASE NEW.status
      WHEN 'approved' THEN 'You''re a church admin'
      WHEN 'rejected' THEN 'Church admin update'
      ELSE 'Church admin status updated' END,
    CASE NEW.status
      WHEN 'approved' THEN 'Your role at ' || COALESCE(cname, 'your church') || ' is approved.'
      WHEN 'rejected' THEN COALESCE(NEW.rejection_reason, 'See the admin screen for details.')
      ELSE 'Your application status has changed.' END,
    'church_admin_status',
    NEW.id::text,
    'church_admin'
  );

  -- 2. The primary admin who nominated them.
  IF NEW.status IN ('approved', 'rejected') THEN
    SELECT ca.user_id INTO primary_id
      FROM public.church_admins ca
     WHERE ca.church_id = NEW.church_id
       AND ca.role      = 'primary'
       AND ca.status    = 'approved'
     LIMIT 1;

    -- Never notify someone about their own row: a primary admin whose own
    -- claim is being decided already gets the message above, and two
    -- notifications for one event reads like a bug.
    IF primary_id IS NOT NULL AND primary_id <> NEW.user_id THEN
      SELECT COALESCE(NULLIF(btrim(p.full_name), ''), 'A member')
        INTO who
        FROM public.profiles p
       WHERE p.id = NEW.user_id;

      INSERT INTO public.notifications (
        user_id, title, body, type, reference_id, reference_type
      ) VALUES (
        primary_id,
        CASE NEW.status
          WHEN 'approved' THEN 'Your nominee was approved'
          ELSE 'Your nominee was not approved' END,
        CASE NEW.status
          WHEN 'approved' THEN
            COALESCE(who, 'A member') || ' is now an admin for '
              || COALESCE(cname, 'your church') || '.'
          ELSE
            COALESCE(who, 'A member') || ' was not approved as an admin'
              -- The reason matters most here: this admin is the one who
              -- has to go back to that member and explain.
              || COALESCE('. Reason: ' || NULLIF(btrim(NEW.rejection_reason), ''),
                          '. No reason was given.')
          END,
        'church_admin_status',
        NEW.id::text,
        'church_admin'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
