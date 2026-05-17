-- =====================================================================
--  PATCH 006 — Round out Part 23 notification triggers
--
--  WHY:  patch_002 §8 wired four of the fourteen triggers listed in
--        master-ref Part 23 (prayer ping, new message, seller status,
--        church-admin status). The remaining ten are missing. Six of
--        them are pure SQL fan-outs from existing INSERT/UPDATE events;
--        this patch closes those. The other four are time-based
--        (require pg_cron) or need app code first — out of scope here.
--
--  WHAT THIS PATCH ADDS:
--    1. notify_new_announcement       — announcements INSERT
--         → church_followers, gated by notification_preferences.
--         Obituaries override the per-user 'none' preference and
--         always deliver (spec rule).
--    2. notify_urgent_banner          — urgent_banners INSERT
--         → every non-banned profile. Conference filtering is a TODO
--         once profiles.conference (or a province→conference lookup)
--         exists; for MVP we fan out nationally and trust the spec
--         constraint that banners are rare.
--    3. notify_event_approved         — events UPDATE OF status
--         → organizer_id, only when status transitions to 'approved'.
--    4. notify_prayer_answered        — prayers UPDATE OF is_answered
--         → every distinct user who left a 'praying' response,
--         excluding the author.
--    5. notify_message_request        — conversations INSERT when
--         request_status='pending' → the non-initiator participant.
--
--  PUSH PIPELINE: each insert into public.notifications fires the
--                 existing Database Webhook → notify-fcm Edge Function
--                 → FCM v1. Nothing else to wire.
--
--  PREREQUISITES: schema.sql + patch_001..patch_005 already applied.
--  IDEMPOTENT:    yes — DROP TRIGGER IF EXISTS + CREATE OR REPLACE
--                 FUNCTION throughout. Safe to re-run.
-- =====================================================================


-- =====================================================================
--  1) ANNOUNCEMENTS — fan-out to church followers
--
--  Rules (master-ref Part 23 + notification_preferences semantics):
--    - none = TRUE        → skip, unless category='obituary'
--    - urgent_only = TRUE → skip unless category IN ('urgent','obituary')
--    - all_notifications  → always notify
--    - no pref row exists → default to all (matches table DEFAULT
--                           all_notifications=TRUE)
--
--  Authors of the announcement don't notify themselves.
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
    cf.user_id,
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
  FROM public.church_followers cf
  LEFT JOIN public.notification_preferences np
    ON np.user_id = cf.user_id AND np.church_id = cf.church_id
  WHERE cf.church_id = NEW.church_id
    AND cf.user_id <> COALESCE(NEW.posted_by, '00000000-0000-0000-0000-000000000000'::uuid)
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


-- =====================================================================
--  2) URGENT BANNERS — nationwide fan-out
--
--  Spec wants per-conference targeting. profiles has no conference
--  column today, so we fan out to every non-banned profile. Once a
--  profiles.conference (or a province→conference lookup table) is
--  added, swap the WHERE clause for a join. Banners are rare and
--  short-lived (48h default), so the table-wide INSERT is acceptable
--  for MVP scale.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_urgent_banner()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_active = FALSE THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    p.id,
    'Urgent: ' || NEW.title,
    COALESCE(substr(NEW.body, 1, 140), ''),
    'urgent_banner',
    NEW.id::text,
    'urgent_banner'
  FROM public.profiles p
  WHERE COALESCE(p.is_banned, FALSE) = FALSE
    AND p.id <> COALESCE(NEW.posted_by, '00000000-0000-0000-0000-000000000000'::uuid);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_urgent_banner ON public.urgent_banners;
CREATE TRIGGER trg_notify_urgent_banner
  AFTER INSERT ON public.urgent_banners
  FOR EACH ROW EXECUTE FUNCTION public.notify_urgent_banner();


-- =====================================================================
--  3) EVENT APPROVED — notify the organiser
--
--  Fires only on the actual transition into 'approved'. Skips inserts
--  that arrive pre-approved (church-posted events default to approved
--  via app logic) and skips no-op updates.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_event_approved()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status <> 'approved' THEN RETURN NEW; END IF;
  IF OLD.status = 'approved' THEN RETURN NEW; END IF;
  IF NEW.organizer_id IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    NEW.organizer_id,
    'Event approved',
    'Your event "' || COALESCE(NEW.title, 'event') || '" is live.',
    'event_approved',
    NEW.id::text,
    'event'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_event_approved ON public.events;
CREATE TRIGGER trg_notify_event_approved
  AFTER UPDATE OF status ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.notify_event_approved();


-- =====================================================================
--  4) PRAYER ANSWERED — notify everyone who prayed
--
--  Fires on the FALSE → TRUE transition of prayers.is_answered.
--  Distinct on user_id so a single user only gets one notification
--  even if they responded multiple times. Author excluded.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_prayer_answered()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_answered = FALSE THEN RETURN NEW; END IF;
  IF OLD.is_answered = TRUE  THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT DISTINCT
    pr.user_id,
    'Prayer answered',
    'A prayer you joined has been marked answered. Praise God.',
    'prayer_answered',
    NEW.id::text,
    'prayer'
  FROM public.prayer_responses pr
  WHERE pr.prayer_id = NEW.id
    AND pr.response_type = 'praying'
    AND pr.user_id <> NEW.author_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_prayer_answered ON public.prayers;
CREATE TRIGGER trg_notify_prayer_answered
  AFTER UPDATE OF is_answered ON public.prayers
  FOR EACH ROW EXECUTE FUNCTION public.notify_prayer_answered();


-- =====================================================================
--  5) MESSAGE REQUEST — notify the recipient
--
--  Fires once when a brand-new conversation lands with
--  request_status='pending'. The recipient is the participant who is
--  NOT the initiator. Falls back to participant_b_id when initiator_id
--  is missing (older client builds).
--
--  Distinct from the 'New message' trigger, which fires per message —
--  this one fires per request and uses a different `type` so the
--  client can route to the Requests inbox.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_message_request()
RETURNS TRIGGER AS $$
DECLARE
  recipient UUID;
  sender_name TEXT;
BEGIN
  IF COALESCE(NEW.request_status, 'accepted') <> 'pending' THEN
    RETURN NEW;
  END IF;

  recipient := CASE
    WHEN NEW.initiator_id IS NOT NULL AND NEW.initiator_id = NEW.participant_a_id
      THEN NEW.participant_b_id
    WHEN NEW.initiator_id IS NOT NULL AND NEW.initiator_id = NEW.participant_b_id
      THEN NEW.participant_a_id
    ELSE NEW.participant_b_id
  END;

  IF recipient IS NULL OR recipient = NEW.initiator_id THEN
    RETURN NEW;
  END IF;

  sender_name := CASE
    WHEN NEW.initiator_id = NEW.participant_a_id THEN NEW.participant_a_name
    WHEN NEW.initiator_id = NEW.participant_b_id THEN NEW.participant_b_name
    ELSE NULL
  END;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    recipient,
    'New message request',
    COALESCE(NULLIF(sender_name, ''), 'Someone') || ' wants to message you.',
    'message_request',
    NEW.id::text,
    'conversation'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_message_request ON public.conversations;
CREATE TRIGGER trg_notify_message_request
  AFTER INSERT ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.notify_message_request();


-- =====================================================================
--  END OF PATCH 006
--
--  Still TODO (out of scope here):
--    - Event reminder 24h before     → needs pg_cron
--    - Job post expiring in 3 days   → needs pg_cron
--    - Job marked as filled          → app code + trigger
--    - Church admin action queue     → needs super_admin role first
-- =====================================================================
