-- =====================================================================
--  RUN_ALL_PENDING.sql — every unapplied patch, in the right order.
--  Generated 1 Nov 2026. Paste the WHOLE file into Supabase → SQL Editor →
--  New query → Run. Each patch is its own transaction (BEGIN … COMMIT),
--  so if one fails, the ones before it stay applied: send Claude the
--  error and the patch number in the header above it.
--
--  NOT included on purpose:
--    * patch_295 (switch encryption on for everyone) — run it alone,
--      after the two-phone test written at the top of that file.
--    * the VACUUM FULL lines from patch_292 — VACUUM can't run inside a
--      script; run each of these on its own afterwards, one at a time:
--        VACUUM FULL public.notifications;
--        VACUUM FULL public.e2ee_prekeys;
--        VACUUM FULL public.app_events;
-- =====================================================================


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_296_group_safety.sql
-- =====================================================================
--  PATCH 296 — group chat security fixes + "only admins can send"
--  STATUS: not yet applied
--
--  Found auditing groups on the live database, 1 Nov 2026:
--
--   1. CRITICAL. _group_system_message() and _group_system_message_meta()
--      are SECURITY DEFINER and executable by every signed-in member.
--      Calling either one directly inserts a message into ANY
--      conversation — including other people's private chats — with ANY
--      sender_id and ANY text, and overwrites that chat's inbox line.
--      That is impersonation. Only the group RPCs (all SECURITY DEFINER,
--      owned by postgres) call them; the app never does. → REVOKE.
--
--   2. is_conversation_admin() ignored left_at: an admin who LEFT, or was
--      removed, kept every admin power — remove members, change roles,
--      rename the group, reset the invite link. → active members only.
--
--   3. leave_group() never checked membership: anyone could post
--      "<name> left" into any conversation id (and rewrite its inbox
--      line). → must be an active member.
--
--   4. When the last admin left, the group had no admin, forever: nobody
--      could add people, rename it or remove a troublemaker. → the
--      longest-standing member is promoted, as WhatsApp does.
--
--   5. set_group_admin() could demote the last admin (same dead end) and
--      notify people who had already left. → refused.
--
--   6. get_or_create_group_invite() let a former member fetch the link.
--      → active members only.
--
--  New (owner's brief: "add features to groups"):
--   7. Announcement mode — "Only admins can send messages". A column, a
--      guarded RPC to flip it, and an insert check so it can't be
--      bypassed from an old app build.
--
--  CLAUDE.md checklist: no profiles change. The new trigger is BEFORE
--  INSERT only and returns NEW (never fires on DELETE).
-- =====================================================================

BEGIN;

-- 1 ------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._group_system_message(bigint, uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._group_system_message_meta(bigint, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;

-- 2 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_conversation_admin(p_conversation bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members m
    WHERE m.conversation_id = p_conversation
      AND m.user_id = auth.uid()
      AND m.role = 'admin'
      AND m.left_at IS NULL
  );
$function$;

-- 3 + 4 ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_group(p_conversation bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor TEXT;
  v_heir  uuid;
  v_heir_name TEXT;
BEGIN
  IF NOT public.is_active_conversation_member(p_conversation) THEN
    RAISE EXCEPTION 'You are not in this group.' USING ERRCODE = '42501';
  END IF;

  -- One leave at a time per group, so two admins leaving together can't
  -- both see "someone else is still admin".
  PERFORM pg_advisory_xact_lock(hashtext('group_leave:' || p_conversation::text));

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'A member') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' left');
  UPDATE public.conversation_members SET left_at = now()
   WHERE conversation_id = p_conversation AND user_id = auth.uid()
     AND left_at IS NULL;

  -- Never leave a group without an admin.
  IF NOT EXISTS (SELECT 1 FROM public.conversation_members
                  WHERE conversation_id = p_conversation
                    AND left_at IS NULL AND role = 'admin') THEN
    SELECT user_id INTO v_heir FROM public.conversation_members
     WHERE conversation_id = p_conversation AND left_at IS NULL
     ORDER BY joined_at ASC NULLS LAST, id ASC
     LIMIT 1;
    IF v_heir IS NOT NULL THEN
      UPDATE public.conversation_members SET role = 'admin'
       WHERE conversation_id = p_conversation AND user_id = v_heir;
      SELECT COALESCE(NULLIF(btrim(full_name), ''), 'A member') INTO v_heir_name
        FROM public.profiles WHERE id = v_heir;
      PERFORM public._group_system_message(p_conversation, v_heir,
        v_heir_name || ' is now an admin');
    END IF;
  END IF;
END;
$function$;

-- 5 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_group_admin(
  p_conversation bigint, p_user_id uuid, p_make_admin boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_actor TEXT; v_group TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can change roles.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversation_members
                  WHERE conversation_id = p_conversation
                    AND user_id = p_user_id AND left_at IS NULL) THEN
    RAISE EXCEPTION 'That person is no longer in this group.';
  END IF;
  IF NOT p_make_admin AND NOT EXISTS (
       SELECT 1 FROM public.conversation_members
        WHERE conversation_id = p_conversation AND left_at IS NULL
          AND role = 'admin' AND user_id <> p_user_id) THEN
    RAISE EXCEPTION 'A group needs at least one admin. Make someone else admin first.';
  END IF;

  UPDATE public.conversation_members
     SET role = CASE WHEN p_make_admin THEN 'admin' ELSE 'member' END
   WHERE conversation_id = p_conversation AND user_id = p_user_id;
  IF p_make_admin THEN
    SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
      FROM public.profiles WHERE id = auth.uid();
    SELECT COALESCE(NULLIF(btrim(name), ''), 'the group') INTO v_group
      FROM public.conversations WHERE id = p_conversation;
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    VALUES (p_user_id, 'Group admin',
            v_actor || ' made you an admin of ' || v_group,
            'message', p_conversation::text, 'conversation');
  END IF;
END;
$function$;

-- 6 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_or_create_group_invite(p_conversation bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_token TEXT;
BEGIN
  IF NOT public.is_active_conversation_member(p_conversation) THEN
    RAISE EXCEPTION 'Only group members can share the invite link.';
  END IF;
  SELECT token INTO v_token
    FROM public.group_invites
   WHERE conversation_id = p_conversation;
  IF v_token IS NULL THEN
    INSERT INTO public.group_invites (token, conversation_id, created_by)
    VALUES (replace(gen_random_uuid()::text, '-', ''), p_conversation, auth.uid())
    ON CONFLICT (conversation_id)
      DO UPDATE SET token = public.group_invites.token
    RETURNING token INTO v_token;
  END IF;
  RETURN v_token;
END;
$function$;

-- 7. Announcement mode -------------------------------------------------
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS admins_only_send boolean NOT NULL DEFAULT false;

-- Members read conversations through their own row policies; the new
-- column rides along (conversations has a table-level grant, unlike
-- profiles — checked).
CREATE OR REPLACE FUNCTION public.set_group_admins_only(
  p_conversation bigint, p_on boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_actor TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can change this.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.conversations SET admins_only_send = p_on
   WHERE id = p_conversation AND is_group AND church_id IS NULL;
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || CASE WHEN p_on
      THEN ' changed this group so only admins can send messages'
      ELSE ' changed this group so everyone can send messages' END);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.set_group_admins_only(bigint, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_admins_only_send()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.message_type = 'system' THEN RETURN NEW; END IF;
  IF auth.uid() IS NULL THEN RETURN NEW; END IF; -- service role / jobs
  IF EXISTS (SELECT 1 FROM public.conversations c
              WHERE c.id = NEW.conversation_id AND c.admins_only_send)
     AND NOT public.is_conversation_admin(NEW.conversation_id) THEN
    RAISE EXCEPTION 'Only admins can send messages in this group.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_admins_only_send ON public.messages;
CREATE TRIGGER trg_admins_only_send
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.enforce_admins_only_send();

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---------------------------------------------------------------------
--  Check (read-only). Expect: false, false, true, the trigger.
-- ---------------------------------------------------------------------
-- SELECT has_function_privilege('authenticated',
--          'public._group_system_message(bigint,uuid,text)', 'EXECUTE') AS helper1,
--        has_function_privilege('authenticated',
--          'public._group_system_message_meta(bigint,uuid,text,jsonb)', 'EXECUTE') AS helper2,
--        (SELECT true FROM information_schema.columns
--          WHERE table_name = 'conversations' AND column_name = 'admins_only_send') AS col,
--        (SELECT tgname FROM pg_trigger WHERE tgname = 'trg_admins_only_send') AS trg;


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_294_e2ee_server_previews.sql
-- =====================================================================
--  PATCH 294 — keep ciphertext out of notifications and inbox previews
--  STATUS: not yet applied
--
--  Needed BEFORE end-to-end encryption is switched on for everyone
--  (patch_295). Checked on the live database 1 Nov 2026:
--
--    * notify_new_message() copies messages.content into the in-app
--      notifications list. For an encrypted message that is base64, so
--      the bell screen would show a line of random characters.
--    * update_conversation_on_message() copies it into
--      conversations.last_message. The app overwrites it with the 🔒
--      sentinel a moment later, but older builds and a failed second
--      write would leave base64 in the inbox.
--    * recompute_conversation_last_message() (after a delete) does the
--      same.
--
--  Now: an encrypted row writes a neutral line — "📷 Photo", "🎙️ Voice
--  note" (the server already knows the message TYPE, only not the
--  content) or "New message" — and the 🔒 sentinel for last_message.
--  Unencrypted messages behave exactly as before.
--
--  CLAUDE.md checklist: no profiles change. All three are AFTER triggers
--  (or called from one); their return values are unchanged.
-- =====================================================================

BEGIN;

-- The neutral line for a message the server cannot read.
CREATE OR REPLACE FUNCTION public.message_public_preview(
  p_content text, p_type text, p_e2ee smallint)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN COALESCE(p_e2ee, 0) > 0 THEN
      CASE p_type
        WHEN 'image' THEN '📷 Photo'
        WHEN 'voice' THEN '🎙️ Voice note'
        ELSE 'New message'
      END
    ELSE p_content
  END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  a uuid; b uuid; other uuid;
  v_is_group boolean; v_group_name text; v_sender_name text;
  v_church_id bigint; v_church_kind text;
  v_body text;
BEGIN
  IF NEW.message_type = 'system' THEN RETURN NEW; END IF;

  -- patch 294: never the ciphertext.
  v_body := public.message_public_preview(
    NEW.content, NEW.message_type, NEW.e2ee_version::smallint);

  SELECT participant_a_id, participant_b_id, is_group, name, church_id, church_kind
    INTO a, b, v_is_group, v_group_name, v_church_id, v_church_kind
    FROM public.conversations WHERE id = NEW.conversation_id;

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone')
    INTO v_sender_name FROM public.profiles WHERE id = NEW.sender_id;

  -- Church conversations (implicit membership via profiles.church_id).
  IF v_church_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    SELECT p.id,
           COALESCE(NULLIF(btrim(v_group_name), ''),
             CASE WHEN v_church_kind = 'channel'
                  THEN 'Church announcement' ELSE 'Church group' END),
           v_sender_name || ': ' || COALESCE(substr(v_body, 1, 120), ''),
           CASE WHEN v_church_kind = 'channel' THEN 'announcement' ELSE 'message' END,
           NEW.conversation_id::text, 'conversation'
      FROM public.profiles p
     WHERE p.church_id = v_church_id
       AND p.id <> NEW.sender_id
       AND COALESCE(p.is_banned, FALSE) = FALSE;
    RETURN NEW;
  END IF;

  IF COALESCE(v_is_group, FALSE) THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    SELECT cm.user_id,
           COALESCE(NULLIF(btrim(v_group_name), ''), 'Group chat'),
           v_sender_name || ': ' || COALESCE(substr(v_body, 1, 120), ''),
           'message', NEW.conversation_id::text, 'conversation'
      FROM public.conversation_members cm
     WHERE cm.conversation_id = NEW.conversation_id
       AND cm.user_id <> NEW.sender_id
       AND cm.left_at IS NULL;
    RETURN NEW;
  END IF;

  IF a IS NULL OR b IS NULL THEN RETURN NEW; END IF;
  other := CASE WHEN NEW.sender_id = a THEN b ELSE a END;
  IF other IS NULL OR other = NEW.sender_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type)
  VALUES (other, v_sender_name,
    COALESCE(substr(v_body, 1, 140), 'You have a new message.'),
    'message', NEW.conversation_id::text, 'conversation');
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.conversations
     SET last_message    = CASE WHEN COALESCE(NEW.e2ee_version, 0) > 0
                                THEN '🔒' ELSE NEW.content END,
         last_message_at = NEW.created_at,
         last_sender_id  = NEW.sender_id,
         updated_at      = NOW()
   WHERE id = NEW.conversation_id;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.recompute_conversation_last_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_content TEXT;
  v_at      TIMESTAMPTZ;
BEGIN
  SELECT CASE WHEN COALESCE(m.e2ee_version, 0) > 0 THEN '🔒' ELSE m.content END,
         m.created_at
    INTO v_content, v_at
    FROM public.messages m
   WHERE m.conversation_id = OLD.conversation_id
   ORDER BY m.created_at DESC
   LIMIT 1;

  UPDATE public.conversations
     SET last_message    = v_content,                  -- NULL when none remain
         last_message_at = COALESCE(v_at, last_message_at)
   WHERE id = OLD.conversation_id;

  RETURN OLD;
END;
$function$;

-- Clean the few that already leaked (8 encrypted messages exist).
UPDATE public.notifications n
   SET body = regexp_replace(n.body, ':\s.*$', ': New message')
 WHERE n.type = 'message'
   AND n.created_at > now() - interval '90 days'
   AND n.reference_id IN (SELECT DISTINCT conversation_id::text
                            FROM public.messages
                           WHERE COALESCE(e2ee_version, 0) > 0)
   AND n.body ~ '[A-Za-z0-9+/]{60,}={0,2}$';

COMMIT;

-- Check (read-only): expect '📷 Photo', 'New message', 'hi'.
-- SELECT public.message_public_preview('xx', 'image', 1::smallint),
--        public.message_public_preview('xx', 'text', 1::smallint),
--        public.message_public_preview('hi', 'text', NULL);


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_297_home_church_only.sql
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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_293_message_client_id_unique.sql
-- =====================================================================
--  PATCH 293 — a message sent twice by a retry is stored once
--  STATUS: not yet applied
--
--  1 Nov 2026, offline chat (owner: "when you send a message [offline] it
--  drafts that message, waiting for internet. Like WhatsApp").
--
--  The app now keeps a message in its outbox whenever the send fails for
--  ANY connection reason — including the case where the insert reached the
--  server but the reply was lost. Retrying that would post it twice. Every
--  message already carries a per-sender client_id; making it unique lets
--  the retry fail with 23505, which the app treats as "already sent".
--
--  Partial on purpose: two duplicates from before (lost-response retries)
--  already exist, and members' old messages are not touched. Only messages
--  from now on are held to it.
--
--  No profiles change, no triggers.
-- =====================================================================

CREATE UNIQUE INDEX IF NOT EXISTS messages_sender_client_id_uniq
  ON public.messages (sender_id, client_id)
  WHERE client_id IS NOT NULL
    AND created_at >= '2026-11-01 00:00:00+00';


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_292_storage_cleanup.sql
-- =====================================================================
--  PATCH 292 — free database space and keep it free
--  STATUS: not yet applied
--
--  Owner, 1 Nov 2026: the Free plan's 500 MB database is at ~392 MB and
--  there is no budget to upgrade. "Only the useful things will take up
--  the storage."
--
--  Measured on the live database before writing this:
--
--    youtube_videos   172 MB   search_tsv alone 61 MB: every word of
--                              every description, 71,735 videos, and NO
--                              index on it (search scanned all rows).
--    notifications     56 MB   78,634 rows; 35,767 daily-devotion,
--                              18,689 YouTube-live, 10,508 Sabbath,
--                              3,946 maintenance, 3,362 admin broadcast,
--                              2,428 quiz nudges — one row PER MEMBER per
--                              broadcast, kept up to 90 days.
--    e2ee_prekeys      32 MB   188,211 spare keys; 117,597 beyond 100 per
--                              device (an app bug uploaded a new batch
--                              whenever the "how many left" check failed;
--                              fixed in e2ee_service.dart, same commit).
--    supabase_functions.hooks  25 MB  webhook call log, 50,073 rows in 5
--                              days; nothing reads it.
--    auth.refresh_tokens 17 MB 49,136 of 49,925 are revoked.
--
--  What this does, nothing a member would miss:
--    1. Video search keeps title + channel + the FIRST 300 characters of
--       the description (where the topic and speaker are), and gets the
--       GIN index patch_154 meant to have (idx_yt_videos_fts was missing).
--       Smaller AND faster — youtube_search timed out on the Nano DB.
--    2. Mass broadcast notifications are kept 7 days (personal ones —
--       messages, likes, friends, prayers — keep the existing 45/90 days).
--    3. Each phone keeps its newest 100 unused encryption prekeys (the
--       app's own batch size); used ones go after 30 days.
--    4. Webhook log kept 2 days (was 7). Revoked login tokens kept 7 days.
--    5. Usage analytics (app_events, app_sessions) kept 120 days.
--    6. All of it runs NOW once, then nightly inside the existing jobs
--       (cleanup-expired-content 03:10, prune-operational-logs 03:50).
--
--  Space: deleting frees room INSIDE the tables for new rows at once. To
--  see the dashboard number drop, run the VACUUM FULL lines at the bottom
--  afterwards, ONE AT A TIME (each takes a few seconds and briefly locks
--  that one table). youtube_videos needs none — step 1 rewrites it.
--
--  CLAUDE.md checklist: no profiles change; no new triggers.
-- =====================================================================

BEGIN;

-- 1. Video search: smaller column + the index it never had ------------
ALTER TABLE public.youtube_videos
  ALTER COLUMN search_tsv SET EXPRESSION AS (
    setweight(to_tsvector('english'::regconfig, COALESCE(title, '')), 'A')
    || setweight(to_tsvector('english'::regconfig,
                             left(COALESCE(description, ''), 300)), 'B')
    || setweight(to_tsvector('english'::regconfig,
                             COALESCE(channel_title, '')), 'C')
  );

CREATE INDEX IF NOT EXISTS idx_yt_videos_fts
  ON public.youtube_videos USING gin (search_tsv);

-- 2-5. Nightly rules, folded into the jobs that already run ------------

-- Broadcast notifications: one row per member per event. A week is
-- plenty for an inbox; the push already reached the phone.
CREATE OR REPLACE FUNCTION public.cleanup_expired_content()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- 1. Expired stories (24h) — actually delete the rows.
  DELETE FROM public.stories WHERE expires_at < now();

  -- 2. Notifications: drop read ones after 45 days and ANY after 90 days
  --    so the table stays small (it's append-only churn).
  DELETE FROM public.notifications
   WHERE (is_read = TRUE AND created_at < now() - INTERVAL '45 days')
      OR created_at < now() - INTERVAL '90 days';

  -- 2b. (patch 292) Mass broadcasts — one row per member each — after 7
  --     days. These were half the table.
  DELETE FROM public.notifications
   WHERE type IN ('devotion', 'youtube_live', 'sabbath_approaching',
                  'sabbath_begins', 'maintenance', 'quiz_nudge',
                  'admin_broadcast', 'birthday', 'profile_incomplete',
                  'ai_service')
     AND created_at < now() - INTERVAL '7 days';

  -- 3. Resolved/dismissed reports older than 60 days.
  DELETE FROM public.reports
   WHERE status IN ('actioned', 'dismissed')
     AND created_at < now() - INTERVAL '60 days';
END;
$function$;

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'cron'
AS $function$
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';

  -- VACUUM FULL removed: Postgres forbids VACUUM inside a function, which made
  -- this whole job fail and roll back. The weekly cron job 'vacuum-operational-logs'
  -- already compacts net._http_response.

  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';

  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';

  DELETE FROM public.call_events WHERE created_at < now() - interval '30 days';

  -- Webhook invocation log; nothing reads it. (patch 292: 7 → 2 days;
  -- ~10,000 rows a day.)
  DELETE FROM supabase_functions.hooks WHERE created_at < now() - interval '2 days';

  -- patch 292: spare encryption prekeys. Each device keeps its newest 100
  -- unused ones (the app's batch size); used ones go after 30 days.
  DELETE FROM public.e2ee_prekeys k
   USING (
     SELECT user_id, device_id, key_id,
            row_number() OVER (PARTITION BY user_id, device_id
                               ORDER BY created_at DESC, key_id DESC) AS rn
       FROM public.e2ee_prekeys
      WHERE claimed_at IS NULL
   ) x
   WHERE x.rn > 100
     AND k.user_id = x.user_id AND k.device_id = x.device_id
     AND k.key_id = x.key_id AND k.claimed_at IS NULL;
  DELETE FROM public.e2ee_prekeys
   WHERE claimed_at IS NOT NULL AND claimed_at < now() - interval '30 days';

  -- patch 292: usage analytics older than 120 days.
  DELETE FROM public.app_events   WHERE created_at < now() - interval '120 days';
  DELETE FROM public.app_sessions WHERE started_at < now() - interval '120 days';

  -- patch 292: revoked login tokens can never be used again. Guarded:
  -- if this role may not touch the auth schema, skip it rather than fail
  -- the whole nightly job.
  BEGIN
    DELETE FROM auth.refresh_tokens
     WHERE revoked AND updated_at < now() - interval '7 days';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'refresh_tokens prune skipped: no privilege';
  END;
END;
$function$;

-- 6. Run both once now ---------------------------------------------------
SELECT public.cleanup_expired_content();
SELECT public.prune_operational_logs();

ANALYZE public.youtube_videos;
ANALYZE public.notifications;
ANALYZE public.e2ee_prekeys;

COMMIT;

-- ---------------------------------------------------------------------
--  AFTERWARDS, to give the space back (run each line ON ITS OWN):
-- ---------------------------------------------------------------------
-- VACUUM FULL public.notifications;
-- VACUUM FULL public.e2ee_prekeys;
-- VACUUM FULL public.app_events;
--
--  Check (read-only):
-- SELECT pg_size_pretty(pg_database_size(current_database())) AS db,
--        pg_size_pretty(pg_total_relation_size('public.youtube_videos')) AS videos,
--        pg_size_pretty(pg_total_relation_size('public.notifications')) AS notifications,
--        pg_size_pretty(pg_total_relation_size('public.e2ee_prekeys')) AS prekeys;


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_298_e2ee_resend.sql
-- =====================================================================
--  PATCH 298 — new encrypted messages always open ("retry receipts")
--  STATUS: not yet applied. Run AFTER patch_294, BEFORE patch_295.
--
--  Owner, 1 Nov 2026: "leave it as 'waiting for this message' — it's
--  fine for old messages, but for new ones don't."
--
--  A NEW message could still be unreadable on the phone it reached:
--    * a group message whose sender key hadn't arrived yet;
--    * a member with two phones — only the newest got the message;
--    * your own message, sent from your other phone.
--  Signal fixes this with "retry receipts": the phone that can't open a
--  message asks, and the sender's phone (which still has the text)
--  re-encrypts that one message for that one device. Same here:
--
--    e2ee_request_resend   the reader's phone asks. Only for messages
--                          sent AFTER this phone registered its keys —
--                          older ones stay "Waiting for this message",
--                          as the owner asked.
--    e2ee_pending_resends  the sender's phone collects requests.
--    e2ee_fulfill_resend   …and answers with a per-device copy.
--    e2ee_copies_for       the reader's phone picks the copy up.
--
--  The server only ever holds ciphertext. A copy is encrypted to one
--  device with that device's own session, like any message.
--
--  Also fixes a key leak: the app claimed (used up) one of the
--  recipient's one-time prekeys on EVERY encrypted send, even with a
--  session already open. e2ee_latest_device lets it skip the claim.
--  claim_prekey_bundle_for claims for one specific device (needed for
--  copies to a member's other phone).
--
--  CLAUDE.md checklist: no profiles change; no triggers. New tables have
--  RLS on and NO policies/grants: they are reached only through these
--  SECURITY DEFINER functions.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.e2ee_resend_requests (
  message_id       bigint NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  requester_user   uuid   NOT NULL,
  requester_device integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  fulfilled_at     timestamptz,
  PRIMARY KEY (message_id, requester_user, requester_device)
);
CREATE INDEX IF NOT EXISTS e2ee_resend_open_idx
  ON public.e2ee_resend_requests (message_id) WHERE fulfilled_at IS NULL;

CREATE TABLE IF NOT EXISTS public.e2ee_message_copies (
  message_id       bigint NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  recipient_user   uuid   NOT NULL,
  recipient_device integer NOT NULL,
  sender_device    integer NOT NULL,
  ciphertext       text   NOT NULL,
  ciphertext_type  integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, recipient_user, recipient_device)
);

ALTER TABLE public.e2ee_resend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.e2ee_message_copies  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.e2ee_resend_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.e2ee_message_copies  FROM PUBLIC, anon, authenticated;

-- Can the caller read this message's conversation right now?
CREATE OR REPLACE FUNCTION public.e2ee_can_read_message(p_message bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.messages m
      JOIN public.conversations c ON c.id = m.conversation_id
     WHERE m.id = p_message
       AND (c.participant_a_id = auth.uid()
            OR c.participant_b_id = auth.uid()
            OR EXISTS (SELECT 1 FROM public.conversation_members cm
                        WHERE cm.conversation_id = c.id
                          AND cm.user_id = auth.uid()
                          AND cm.left_at IS NULL))
  );
$function$;
REVOKE EXECUTE ON FUNCTION public.e2ee_can_read_message(bigint) FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.e2ee_latest_device(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN public.is_blocked_by(p_user) THEN NULL ELSE (
    SELECT d.device_id FROM public.e2ee_devices d
     WHERE d.user_id = p_user
     ORDER BY d.last_seen_at DESC
     LIMIT 1) END;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_latest_device(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_prekey_bundle_for(p_user uuid, p_device integer)
RETURNS TABLE(device_id integer, registration_id integer, identity_key text,
              signed_key_id integer, signed_key text, signed_sig text,
              prekey_id integer, prekey text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_prekey RECORD;
BEGIN
  IF public.is_blocked_by(p_user) THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.e2ee_devices d
                  WHERE d.user_id = p_user AND d.device_id = p_device) THEN
    RETURN;
  END IF;

  UPDATE public.e2ee_prekeys k
     SET claimed_at = NOW()
   WHERE (k.user_id, k.device_id, k.key_id) = (
     SELECT s.user_id, s.device_id, s.key_id
       FROM public.e2ee_prekeys s
      WHERE s.user_id = p_user AND s.device_id = p_device
        AND s.claimed_at IS NULL
      ORDER BY s.key_id
      FOR UPDATE SKIP LOCKED
      LIMIT 1
   )
  RETURNING k.key_id, k.public_key INTO v_prekey;

  RETURN QUERY
  SELECT d.device_id, d.registration_id, d.identity_key,
         sp.key_id, sp.public_key, sp.signature,
         v_prekey.key_id, v_prekey.public_key
    FROM public.e2ee_devices d
    JOIN public.e2ee_signed_prekeys sp
      ON sp.user_id = d.user_id AND sp.device_id = d.device_id
   WHERE d.user_id = p_user AND d.device_id = p_device
   ORDER BY sp.created_at DESC
   LIMIT 1;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.claim_prekey_bundle_for(uuid, integer) TO authenticated;

-- The reader asks. Returns true if a request is now open.
CREATE OR REPLACE FUNCTION public.e2ee_request_resend(p_message bigint, p_device integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_registered timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  SELECT d.created_at INTO v_registered FROM public.e2ee_devices d
   WHERE d.user_id = auth.uid() AND d.device_id = p_device;
  IF v_registered IS NULL THEN RETURN false; END IF;
  IF NOT public.e2ee_can_read_message(p_message) THEN RETURN false; END IF;
  -- New messages only: anything older than this phone's keys stays
  -- "Waiting for this message" (owner's call).
  IF NOT EXISTS (SELECT 1 FROM public.messages m
                  WHERE m.id = p_message
                    AND COALESCE(m.e2ee_version, 0) > 0
                    AND m.created_at >= v_registered - interval '2 minutes') THEN
    RETURN false;
  END IF;
  INSERT INTO public.e2ee_resend_requests (message_id, requester_user, requester_device)
  VALUES (p_message, auth.uid(), p_device)
  ON CONFLICT DO NOTHING;
  RETURN true;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_request_resend(bigint, integer) TO authenticated;

-- The sender collects open requests for messages they sent.
CREATE OR REPLACE FUNCTION public.e2ee_pending_resends()
RETURNS TABLE(message_id bigint, requester_user uuid, requester_device integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT r.message_id, r.requester_user, r.requester_device
    FROM public.e2ee_resend_requests r
    JOIN public.messages m ON m.id = r.message_id
   WHERE m.sender_id = auth.uid()
     AND r.fulfilled_at IS NULL
     AND r.created_at > now() - interval '30 days'
   ORDER BY r.created_at
   LIMIT 200;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_pending_resends() TO authenticated;

-- The sender answers with one device's copy.
CREATE OR REPLACE FUNCTION public.e2ee_fulfill_resend(
  p_message bigint, p_user uuid, p_device integer,
  p_sender_device integer, p_ciphertext text, p_type integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.messages m
                  WHERE m.id = p_message AND m.sender_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not your message.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.e2ee_resend_requests r
                  WHERE r.message_id = p_message AND r.requester_user = p_user
                    AND r.requester_device = p_device) THEN
    RAISE EXCEPTION 'Nobody asked for this copy.' USING ERRCODE = '42501';
  END IF;
  IF length(p_ciphertext) > 200000 THEN
    RAISE EXCEPTION 'Too large.' USING ERRCODE = '22001';
  END IF;
  INSERT INTO public.e2ee_message_copies (message_id, recipient_user,
    recipient_device, sender_device, ciphertext, ciphertext_type)
  VALUES (p_message, p_user, p_device, p_sender_device, p_ciphertext, p_type)
  ON CONFLICT (message_id, recipient_user, recipient_device) DO UPDATE
    SET sender_device = EXCLUDED.sender_device,
        ciphertext = EXCLUDED.ciphertext,
        ciphertext_type = EXCLUDED.ciphertext_type,
        created_at = now();
  UPDATE public.e2ee_resend_requests SET fulfilled_at = now()
   WHERE message_id = p_message AND requester_user = p_user
     AND requester_device = p_device;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_fulfill_resend(bigint, uuid, integer, integer, text, integer) TO authenticated;

-- The reader picks copies up.
CREATE OR REPLACE FUNCTION public.e2ee_copies_for(p_messages bigint[], p_device integer)
RETURNS TABLE(message_id bigint, sender_id uuid, sender_device integer,
              ciphertext text, ciphertext_type integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT c.message_id, m.sender_id, c.sender_device, c.ciphertext, c.ciphertext_type
    FROM public.e2ee_message_copies c
    JOIN public.messages m ON m.id = c.message_id
   WHERE c.recipient_user = auth.uid()
     AND c.recipient_device = p_device
     AND c.message_id = ANY (p_messages[1:200]);
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_copies_for(bigint[], integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Copies and requests are small and short-lived; prune after 30 days.
-- (Added to prune_operational_logs in a later patch if they grow.)
-- Check (read-only): expect 2 tables, 6 functions.
-- SELECT count(*) FROM pg_tables WHERE tablename IN ('e2ee_resend_requests','e2ee_message_copies');
-- SELECT count(*) FROM pg_proc WHERE proname IN ('e2ee_latest_device','claim_prekey_bundle_for',
--   'e2ee_request_resend','e2ee_pending_resends','e2ee_fulfill_resend','e2ee_copies_for');


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_299_prune_e2ee_copies.sql
-- =====================================================================
--  PATCH 299 — keep the re-send tables small
--  STATUS: not yet applied. Run AFTER patch_298 and patch_292.
--
--  patch_298's request/copy tables only matter until the reader's phone
--  has picked a copy up. Copies older than 30 days and fulfilled
--  requests older than 7 days are pruned nightly, inside the existing
--  prune-operational-logs job (restated in full from patch_292).
--
--  CLAUDE.md checklist: no profiles change; no triggers.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'cron'
AS $function$
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';
  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';
  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';
  DELETE FROM public.call_events WHERE created_at < now() - interval '30 days';
  DELETE FROM supabase_functions.hooks WHERE created_at < now() - interval '2 days';

  DELETE FROM public.e2ee_prekeys k
   USING (
     SELECT user_id, device_id, key_id,
            row_number() OVER (PARTITION BY user_id, device_id
                               ORDER BY created_at DESC, key_id DESC) AS rn
       FROM public.e2ee_prekeys
      WHERE claimed_at IS NULL
   ) x
   WHERE x.rn > 100
     AND k.user_id = x.user_id AND k.device_id = x.device_id
     AND k.key_id = x.key_id AND k.claimed_at IS NULL;
  DELETE FROM public.e2ee_prekeys
   WHERE claimed_at IS NOT NULL AND claimed_at < now() - interval '30 days';

  -- patch 299: re-send copies and requests (patch_298).
  DELETE FROM public.e2ee_message_copies
   WHERE created_at < now() - interval '30 days';
  DELETE FROM public.e2ee_resend_requests
   WHERE (fulfilled_at IS NOT NULL AND fulfilled_at < now() - interval '7 days')
      OR created_at < now() - interval '30 days';

  DELETE FROM public.app_events   WHERE created_at < now() - interval '120 days';
  DELETE FROM public.app_sessions WHERE started_at < now() - interval '120 days';

  BEGIN
    DELETE FROM auth.refresh_tokens
     WHERE revoked AND updated_at < now() - interval '7 days';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'refresh_tokens prune skipped: no privilege';
  END;
END;
$function$;

COMMIT;


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_300_story_e2ee.sql
-- =====================================================================
--  PATCH 300 — end-to-end encrypted stories
--  STATUS: not yet applied. Needs patch_298 first (same E2EE family).
--
--  Stories are already friends-only (policy stories_select_active), so
--  each one has a known audience at posting time. The app now:
--    * seals a story photo with its own AES-256-GCM key (the bucket gets
--      ciphertext), and puts the key, the text and the caption in a small
--      envelope;
--    * encrypts that envelope once for each friend's current phone with
--      the 1:1 Signal session chat already uses, and stores those wraps in
--      story_keys. The stories row itself then carries no readable text.
--
--  A friend on an old build (no keys) sees "Update the app to see this
--  story". A story stays readable to its own author on the phone that
--  posted it. Unencrypted stories (encryption off) are unchanged.
--
--  CLAUDE.md checklist: no profiles change; no triggers. story_keys has
--  RLS on and no policies/grants — reached only through the functions.
-- =====================================================================

BEGIN;

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS e2ee_version smallint;

CREATE TABLE IF NOT EXISTS public.story_keys (
  story_id         uuid    NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
  recipient_user   uuid    NOT NULL,
  recipient_device integer NOT NULL,
  sender_device    integer NOT NULL,
  ciphertext       text    NOT NULL,
  ciphertext_type  integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, recipient_user, recipient_device)
);
ALTER TABLE public.story_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.story_keys FROM PUBLIC, anon, authenticated;

-- The author hands out wraps for their own story, to accepted friends only.
CREATE OR REPLACE FUNCTION public.story_add_keys(p_story uuid, p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer := 0;
  r jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.stories s
                  WHERE s.id = p_story AND s.author_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not your story.' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) > 2000 THEN
    RAISE EXCEPTION 'Bad key list.' USING ERRCODE = '22023';
  END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    -- Only friends (and the author's own other phones) may get a key.
    IF (r->>'u')::uuid <> auth.uid() AND NOT EXISTS (
         SELECT 1 FROM public.friendships f
          WHERE f.status = 'accepted'
            AND ((f.requester_id = auth.uid() AND f.addressee_id = (r->>'u')::uuid)
              OR (f.addressee_id = auth.uid() AND f.requester_id = (r->>'u')::uuid))) THEN
      CONTINUE;
    END IF;
    IF length(r->>'c') > 20000 THEN CONTINUE; END IF;
    INSERT INTO public.story_keys (story_id, recipient_user, recipient_device,
      sender_device, ciphertext, ciphertext_type)
    VALUES (p_story, (r->>'u')::uuid, (r->>'d')::int, (r->>'s')::int,
            r->>'c', (r->>'t')::int)
    ON CONFLICT (story_id, recipient_user, recipient_device) DO UPDATE
      SET ciphertext = EXCLUDED.ciphertext,
          ciphertext_type = EXCLUDED.ciphertext_type,
          sender_device = EXCLUDED.sender_device;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.story_add_keys(uuid, jsonb) TO authenticated;

-- A viewer picks up the wraps for stories they can see, for one phone.
CREATE OR REPLACE FUNCTION public.story_keys_for(p_stories uuid[], p_device integer)
RETURNS TABLE(story_id uuid, sender_device integer, ciphertext text, ciphertext_type integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT k.story_id, k.sender_device, k.ciphertext, k.ciphertext_type
    FROM public.story_keys k
    JOIN public.stories s ON s.id = k.story_id
   WHERE k.recipient_user = auth.uid()
     AND k.recipient_device = p_device
     AND s.expires_at > now()
     AND k.story_id = ANY (p_stories[1:300]);
$function$;
GRANT EXECUTE ON FUNCTION public.story_keys_for(uuid[], integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> database/patch_301_chat_backups.sql
-- =====================================================================
--  PATCH 301 — private storage for end-to-end encrypted chat backups
--  STATUS: not yet applied.
--
--  The app seals each member's readable chat history with a key derived
--  from a password only they know (ChatBackupService), and uploads the
--  sealed file to chat_backups/<their user id>/backup.bin. This bucket is
--  private and each member can only touch their own folder. The server
--  holds ciphertext; without the member's password nobody can open it.
--
--  CLAUDE.md checklist: no profiles change; no triggers.
-- =====================================================================

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('chat_backups', 'chat_backups', false, 52428800)  -- 50 MB
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS chat_backups_own_select ON storage.objects;
DROP POLICY IF EXISTS chat_backups_own_insert ON storage.objects;
DROP POLICY IF EXISTS chat_backups_own_update ON storage.objects;
DROP POLICY IF EXISTS chat_backups_own_delete ON storage.objects;

CREATE POLICY chat_backups_own_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'chat_backups'
         AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY chat_backups_own_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_backups'
              AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY chat_backups_own_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'chat_backups'
         AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'chat_backups'
              AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY chat_backups_own_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'chat_backups'
         AND (storage.foldername(name))[1] = auth.uid()::text);

COMMIT;
