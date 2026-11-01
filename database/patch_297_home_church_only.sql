-- =====================================================================
--  PATCH 297 — one church per member: the home church
--  STATUS: not yet applied
--
--  Owner, 1 Nov 2026: "Remove the Follow button on churches. Members only
--  belong to their home church… To follow another church, it must create
--  a Page." The app no longer offers following (same release). This
--  brings the server in line, so admins see and reach their real members:
--
--   1. church_member_list / church_member_count / church_admin_stats
--      counted church_FOLLOWERS. Now: members whose profiles.church_id is
--      this church (328 members have one set today).
--   2. fanout_announcement sent to followers UNION members. Now: members
--      only — a church's announcements reach its own congregation.
--   3. The 9 follows of a church that is NOT the member's home church are
--      removed (checked live: 334 follows, 325 of them the home church).
--      Following one's own home church is harmless and kept.
--
--  CLAUDE.md checklist: no profiles change; no triggers. Signatures and
--  security settings are restated exactly as they are live.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.church_member_list(p_church_id bigint)
RETURNS TABLE(user_id uuid, full_name text, profile_photo_url text,
              joined_at timestamp with time zone)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id, p.full_name, p.profile_photo_url, p.created_at
    FROM public.profiles p
   WHERE p.church_id = p_church_id
     AND COALESCE(p.is_banned, FALSE) = FALSE
     AND (
       public.is_super_admin()
       OR EXISTS (
         SELECT 1 FROM public.church_admins ca
          WHERE ca.church_id = p_church_id
            AND ca.user_id = auth.uid()
            AND ca.status = 'approved'
       )
     )
   ORDER BY p.full_name ASC NULLS LAST;
$function$;

CREATE OR REPLACE FUNCTION public.church_member_count(p_church_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN public.is_super_admin()
      OR EXISTS (
        SELECT 1 FROM public.church_admins ca
         WHERE ca.church_id = p_church_id
           AND ca.user_id = auth.uid()
           AND ca.status = 'approved'
      )
    THEN (SELECT count(*)::int FROM public.profiles p
           WHERE p.church_id = p_church_id
             AND COALESCE(p.is_banned, FALSE) = FALSE)
    ELSE 0
  END;
$function$;

CREATE OR REPLACE FUNCTION public.church_admin_stats(p_church_id bigint)
RETURNS TABLE(members integer, announcements integer, events integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    (SELECT count(*)::int FROM public.profiles p
      WHERE p.church_id = p_church_id
        AND COALESCE(p.is_banned, FALSE) = FALSE),
    (SELECT count(*)::int FROM public.announcements a WHERE a.church_id = p_church_id),
    (SELECT count(*)::int FROM public.events e WHERE e.church_id = p_church_id)
  WHERE (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.church_admins ca
       WHERE ca.church_id = p_church_id
         AND ca.user_id = auth.uid()
         AND ca.status = 'approved'
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fanout_announcement(p_id bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  a            public.announcements%ROWTYPE;
  cname        TEXT;
  is_obituary  BOOLEAN;
  is_urgent    BOOLEAN;
  v_count      INTEGER := 0;
BEGIN
  SELECT * INTO a FROM public.announcements WHERE id = p_id;
  IF a.id IS NULL THEN RETURN 0; END IF;
  IF a.notified_at IS NOT NULL THEN RETURN 0; END IF;

  is_obituary := (a.category = 'obituary');
  is_urgent   := (a.category IN ('urgent','obituary'));
  SELECT name INTO cname FROM public.churches WHERE id = a.church_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    aud.user_id,
    CASE
      WHEN is_obituary THEN 'Obituary from ' || COALESCE(cname, 'your church')
      WHEN a.category = 'urgent' THEN 'Urgent: ' || a.title
      ELSE COALESCE(cname, 'Your church') || ' posted an update'
    END,
    COALESCE(substr(a.title, 1, 140), ''),
    CASE
      WHEN is_obituary THEN 'announcement_obituary'
      WHEN a.category = 'urgent' THEN 'announcement_urgent'
      ELSE 'announcement'
    END,
    a.id::text,
    'announcement'
  FROM (
    -- patch_297: the church's own members — home church only.
    SELECT p.id AS user_id FROM public.profiles p
     WHERE p.church_id = a.church_id
       AND COALESCE(p.is_banned, FALSE) = FALSE
  ) AS aud
  LEFT JOIN public.notification_preferences np
    ON np.user_id = aud.user_id AND np.church_id = a.church_id
  WHERE aud.user_id <> COALESCE(a.posted_by, '00000000-0000-0000-0000-000000000000'::uuid)
    AND (
      np.id IS NULL
      OR is_obituary
      OR (np.urgent_only = TRUE AND is_urgent)
      OR (np.all_notifications = TRUE AND COALESCE(np.none, FALSE) = FALSE)
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.announcements
     SET sent_count = v_count, notified_at = NOW()
   WHERE id = p_id;

  RETURN v_count;
END;
$function$;

-- 3. Follows of a church that is not the member's home church.
DELETE FROM public.church_followers f
 USING public.profiles p
 WHERE p.id = f.user_id
   AND p.church_id IS DISTINCT FROM f.church_id;

COMMIT;

-- Check (read-only): expect 0.
-- SELECT count(*) FROM public.church_followers f
--   JOIN public.profiles p ON p.id = f.user_id
--  WHERE p.church_id IS DISTINCT FROM f.church_id;
