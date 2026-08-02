-- Who can message me — and how far a stranger gets before you decide.
--
-- Founder call, 2 Aug 2026: "a stranger can only send one message before
-- you accept the friend request."
--
-- A cap already existed (patch_118, `enforce_non_friend_message_cap`) but
-- it allowed THREE messages and lifted as soon as the recipient replied.
-- This tightens it to one and hangs the gate on the friend request, then
-- adds the member-facing setting that decides whether a stranger may
-- reach them at all.
--
-- Replying still lifts every gate. Answering someone is a stronger act of
-- consent than accepting a friend request, and 145 conversations were
-- already sitting in `request_status = 'pending'` when this shipped —
-- removing that lift would have re-gated live threads.

-- 1. The setting itself. Defaults to 'everyone' so nothing changes for
--    anyone who never opens Chat settings.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS who_can_message TEXT NOT NULL DEFAULT 'everyone';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_who_can_message_check'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_who_can_message_check
      CHECK (who_can_message IN ('everyone', 'friends', 'nobody'));
  END IF;
END $$;

COMMENT ON COLUMN public.profiles.who_can_message IS
  'everyone = strangers get one message until the friend request is '
  'accepted; friends = only accepted friends may send; nobody = no one '
  'may OPEN a new conversation (threads already spoken in continue).';

-- 2. The gate. SECURITY DEFINER because it reads the recipient's profile
--    row, which the sender cannot select under RLS.
CREATE OR REPLACE FUNCTION public.enforce_non_friend_message_cap()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_is_group BOOLEAN;
  v_a uuid;
  v_b uuid;
  v_other uuid;
  v_sent INT;
  v_replied BOOLEAN;
  v_friends BOOLEAN;
  v_pref TEXT;
BEGIN
  SELECT is_group, participant_a_id, participant_b_id
    INTO v_is_group, v_a, v_b
    FROM public.conversations
    WHERE id = NEW.conversation_id;

  -- Only gate 1:1 chats with two known participants. Groups and church
  -- channels have their own membership rules.
  IF COALESCE(v_is_group, FALSE) OR v_a IS NULL OR v_b IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.sender_id = v_a THEN
    v_other := v_b;
  ELSIF NEW.sender_id = v_b THEN
    v_other := v_a;
  ELSE
    RETURN NEW; -- sender isn't a participant (shouldn't happen)
  END IF;

  -- A reply lifts everything. Whatever the recipient's setting says, they
  -- have spoken to this person, and re-gating a live thread because they
  -- later set "nobody" would silently break a conversation in progress.
  SELECT EXISTS (
    SELECT 1 FROM public.messages
    WHERE conversation_id = NEW.conversation_id
      AND sender_id = v_other
  ) INTO v_replied;
  IF v_replied THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(who_can_message, 'everyone')
    INTO v_pref
    FROM public.profiles
    WHERE id = v_other;
  v_pref := COALESCE(v_pref, 'everyone');

  v_friends := public.are_friends(NEW.sender_id, v_other);

  -- 'nobody' stops the conversation being OPENED at all — friends
  -- included. It is the only setting that gates a friend, which is why it
  -- is checked before the friendship shortcut.
  IF v_pref = 'nobody' THEN
    RAISE EXCEPTION
      'This person is not accepting new messages.'
      USING ERRCODE = 'check_violation',
            HINT = 'They have turned off new conversations in Chat settings.';
  END IF;

  IF v_friends THEN
    RETURN NEW;
  END IF;

  IF v_pref = 'friends' THEN
    RAISE EXCEPTION
      'This person only accepts messages from friends.'
      USING ERRCODE = 'check_violation',
            HINT = 'Send a friend request first.';
  END IF;

  -- 'everyone': one message, then wait to be accepted.
  SELECT count(*) INTO v_sent
    FROM public.messages
    WHERE conversation_id = NEW.conversation_id
      AND sender_id = NEW.sender_id;

  IF v_sent >= 1 THEN
    RAISE EXCEPTION
      'You can send one message until they accept your friend request.'
      USING ERRCODE = 'check_violation',
            HINT = 'Wait for them to accept, or for a reply.';
  END IF;

  RETURN NEW;
END;
$function$;
