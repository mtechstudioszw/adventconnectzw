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
