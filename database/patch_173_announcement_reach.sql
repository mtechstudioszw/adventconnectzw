-- =====================================================================
--  PATCH 173 — Announcement reach: delivery counts + read receipts
--
--  WHY: the church admin dashboard shows an announcement-reach sparkline,
--  and the founder asked (2026-07-28) for OPENS, not just sends. Nothing
--  in the schema recorded either.
--
--  WHAT:
--    1. announcements.sent_count / notified_at — how many notifications
--       the fan-out actually wrote, stamped once, at fan-out time. Cheap
--       to read forever after; counting notifications rows on demand
--       would mean scanning a 51k-row table by an untyped TEXT
--       reference_id.
--    2. announcement_reads — one row per member who opened it. Members
--       can write and read only their OWN row; admins never see who read
--       what, only totals, and only through the RPC below. A church
--       admin knowing exactly which members ignore them is a different
--       product with different consent, so the aggregate is the ceiling.
--    3. fanout_announcement(id) — the fan-out body lifted out of the
--       trigger so patch_174's scheduled publisher can call the SAME
--       code path. notified_at makes it idempotent: a double-publish
--       can never notify a congregation twice.
--    4. church_announcement_reach(church_id) — sent + read per
--       announcement, for approved admins of that church only.
--
--  The audience (followers ∪ members) and the preference logic are
--  carried over from patch_171 UNCHANGED.
--
--  RLS: creates policies on a NEW table only. No existing policy is
--  read, altered or dropped.
--  IDEMPOTENT: yes.
-- =====================================================================

ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS sent_count  INTEGER,
  ADD COLUMN IF NOT EXISTS notified_at TIMESTAMPTZ;


-- ---------------------------------------------------------------------
--  Read receipts
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.announcement_reads (
  announcement_id BIGINT      NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
  user_id         UUID        NOT NULL REFERENCES public.profiles(id)      ON DELETE CASCADE,
  read_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (announcement_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_announcement_reads_announcement
  ON public.announcement_reads (announcement_id);

ALTER TABLE public.announcement_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS announcement_reads_insert_own ON public.announcement_reads;
CREATE POLICY announcement_reads_insert_own ON public.announcement_reads
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS announcement_reads_select_own ON public.announcement_reads;
CREATE POLICY announcement_reads_select_own ON public.announcement_reads
  FOR SELECT TO authenticated USING (user_id = auth.uid());


-- ---------------------------------------------------------------------
--  The fan-out, callable on its own.
--
--  Returns the number of notifications written. Returns 0 without doing
--  anything if this announcement has already been fanned out.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fanout_announcement(p_id BIGINT)
RETURNS INTEGER AS $$
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
    -- patch_171: followers of the church, UNION people who belong to it.
    SELECT cf.user_id FROM public.church_followers cf WHERE cf.church_id = a.church_id
    UNION
    SELECT p.id       FROM public.profiles p          WHERE p.church_id = a.church_id
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.fanout_announcement(BIGINT) FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  Trigger: publish-on-insert unless it is scheduled for later.
--  (The publisher for scheduled rows arrives in patch_174.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_new_announcement()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.publish_at IS NOT NULL AND NEW.publish_at > NOW() THEN
    RETURN NEW;                      -- scheduled; the cron job posts it
  END IF;
  PERFORM public.fanout_announcement(NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_new_announcement ON public.announcements;
CREATE TRIGGER trg_notify_new_announcement
  AFTER INSERT ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_announcement();

-- Announcements that pre-date this patch were fanned out by the old
-- trigger, so mark them notified — otherwise patch_174's publisher would
-- treat the whole back catalogue as due and re-notify everyone.
UPDATE public.announcements
   SET notified_at = COALESCE(notified_at, created_at)
 WHERE notified_at IS NULL;


-- ---------------------------------------------------------------------
--  Reach, for the admin dashboard sparkline.
--
--  Aggregates only. Approved admins of THIS church, or the super admin.
--  Everyone else gets an empty set, not an error — the dashboard renders
--  "no data yet" rather than a failure.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.church_announcement_reach(
  p_church_id BIGINT, p_limit INTEGER DEFAULT 8
)
RETURNS TABLE (
  id           BIGINT,
  title        TEXT,
  category     TEXT,
  created_at   TIMESTAMPTZ,
  sent_count   INTEGER,
  read_count   INTEGER
)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT a.id, a.title, a.category, a.created_at,
         COALESCE(a.sent_count, 0),
         (SELECT count(*)::int FROM public.announcement_reads r
           WHERE r.announcement_id = a.id)
    FROM public.announcements a
   WHERE a.church_id = p_church_id
     AND a.notified_at IS NOT NULL
     AND (
       public.is_super_admin()
       OR EXISTS (
         SELECT 1 FROM public.church_admins ca
          WHERE ca.church_id = p_church_id
            AND ca.user_id = auth.uid()
            AND ca.status = 'approved'
       )
     )
   ORDER BY a.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 8), 30));
$$;

REVOKE ALL ON FUNCTION public.church_announcement_reach(BIGINT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_announcement_reach(BIGINT, INTEGER) TO authenticated;


-- =====================================================================
--  VERIFY
--    SELECT id, title, sent_count, notified_at FROM announcements
--     ORDER BY created_at DESC LIMIT 5;
--  Post a test announcement: sent_count should equal the reach_now count
--  from patch_171's verify query, minus the poster.
-- =====================================================================
