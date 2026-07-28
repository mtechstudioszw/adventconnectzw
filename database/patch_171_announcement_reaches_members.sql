-- =====================================================================
--  PATCH 171 — Announcements must reach MEMBERS, not just followers
--
--  BUG (confirmed 2026-07-28): patch_006's notify_new_announcement fans
--  out `FROM public.church_followers` and nothing else. Following a
--  church is an explicit opt-in tap on the church profile; belonging to
--  one is `profiles.church_id`, set during profile setup. They are not
--  the same people. A member who never tapped Follow on their OWN
--  congregation received no announcement at all — not even an obituary,
--  which the spec says must always deliver.
--
--  FIX: fan out to followers UNION members of the church.
--    * UNION (not UNION ALL) dedupes the overlap — most members do also
--      follow, and they must not get the notification twice.
--    * The preference logic is UNCHANGED, deliberately. obituary-always
--      and urgent-only were verified correct; this patch only widens WHO
--      is considered, never WHAT they are considered for.
--    * notification_preferences is keyed UNIQUE (user_id, church_id), so
--      the LEFT JOIN still cannot multiply rows.
--
--  NOT CHANGED: no is_banned filter is introduced here. The follower
--  path never had one, and adding it in the same patch would hide a
--  second behaviour change inside a fix. Worth doing separately.
--
--  RLS: none touched. This patch replaces one SECURITY DEFINER trigger
--  function and nothing else — no policy is dropped or created.
--
--  PREREQUISITES: patch_006 applied.
--  IDEMPOTENT:    yes — CREATE OR REPLACE FUNCTION + DROP/CREATE TRIGGER.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_new_announcement()
RETURNS TRIGGER AS $$
DECLARE
  cname        TEXT;
  is_obituary  BOOLEAN := (NEW.category = 'obituary');
  is_urgent    BOOLEAN := (NEW.category IN ('urgent','obituary'));
BEGIN
  SELECT name INTO cname FROM public.churches WHERE id = NEW.church_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    aud.user_id,
    CASE
      WHEN is_obituary THEN 'Obituary from ' || COALESCE(cname, 'your church')
      WHEN NEW.category = 'urgent' THEN 'Urgent: ' || NEW.title
      ELSE COALESCE(cname, 'Your church') || ' posted an update'
    END,
    COALESCE(substr(NEW.title, 1, 140), ''),
    CASE
      WHEN is_obituary THEN 'announcement_obituary'
      WHEN NEW.category = 'urgent' THEN 'announcement_urgent'
      ELSE 'announcement'
    END,
    NEW.id::text,
    'announcement'
  FROM (
    -- Everyone who should hear from this church: people who chose to
    -- follow it, and people who belong to it.
    SELECT cf.user_id
      FROM public.church_followers cf
     WHERE cf.church_id = NEW.church_id
    UNION
    SELECT p.id
      FROM public.profiles p
     WHERE p.church_id = NEW.church_id
  ) AS aud
  LEFT JOIN public.notification_preferences np
    ON np.user_id = aud.user_id AND np.church_id = NEW.church_id
  WHERE aud.user_id <> COALESCE(NEW.posted_by, '00000000-0000-0000-0000-000000000000'::uuid)
    AND (
      -- Default to deliver if no pref row exists.
      np.id IS NULL
      -- Obituary always wins.
      OR is_obituary
      -- Urgent-only allows urgent + obituary.
      OR (np.urgent_only = TRUE AND is_urgent)
      -- Full opt-in, and not muted.
      OR (np.all_notifications = TRUE AND COALESCE(np.none, FALSE) = FALSE)
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_new_announcement ON public.announcements;
CREATE TRIGGER trg_notify_new_announcement
  AFTER INSERT ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_announcement();


-- ---------------------------------------------------------------------
--  Supporting index. profiles already has idx_profiles_church_id
--  (schema.sql:94), so the members arm is covered; church_followers has
--  idx_church_followers_church. Nothing further to add — this note
--  exists so the next reader doesn't go looking.
-- ---------------------------------------------------------------------


-- =====================================================================
--  VERIFY (run after applying, before posting a real announcement)
--
--  How many people a church can now reach, and how many of them the
--  follower-only fan-out was missing:
--
--    SELECT c.id, c.name,
--           (SELECT count(*) FROM church_followers f WHERE f.church_id = c.id)
--             AS followers,
--           (SELECT count(*) FROM profiles p WHERE p.church_id = c.id)
--             AS members,
--           (SELECT count(*) FROM (
--              SELECT user_id FROM church_followers WHERE church_id = c.id
--              UNION
--              SELECT id FROM profiles WHERE church_id = c.id) u)
--             AS reach_now
--      FROM churches c
--     ORDER BY reach_now DESC
--     LIMIT 20;
--
--  reach_now > followers on any row is a member who was hearing nothing.
-- =====================================================================
