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
