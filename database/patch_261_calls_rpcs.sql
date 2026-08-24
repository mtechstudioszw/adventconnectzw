-- =====================================================================
--  PATCH 261 — Audio calling: the server-side rules
--
--  Every call transition lives here, behind SECURITY DEFINER RPCs. The
--  Flutter client cannot INSERT, UPDATE or DELETE a single row in any
--  calls table (patch_260 grants SELECT and nothing else), so this file
--  is the whole authorisation surface for the feature.
--
--  ## The rule this file exists to enforce
--
--  **Nothing the client says about identity is believed.** Not the
--  caller id, not the recipient, not the group, not "I accepted", not
--  "the call lasted 40 minutes". Caller identity is always `auth.uid()`
--  from the JWT. Durations are computed from server timestamps the
--  server itself stamped. A client that posts `call_accept` for a call
--  it was never invited to gets a refusal, not a call.
--
--  ## Why these RPCs RETURN errors instead of RAISEing them
--
--  This is the one non-obvious decision in the file, and it is load
--  bearing.
--
--  Rate limiting here uses `check_and_consume_rate_limit` (patch_026),
--  which records the attempt by INSERTing a row. A function that
--  consumes a token and then RAISEs rolls that INSERT back with
--  everything else — so **every refused call would cost the caller
--  nothing**, and the attempt ceiling would only ever limit calls that
--  succeeded. An attacker hammering someone who blocked them would be
--  refused forever, at no cost, forever.
--
--  So the state-changing RPCs return `{"error": "<CODE>", "message":
--  "<human text>"}` and COMMIT. The token stays spent, the audit event
--  stays written, and `CallApi` in Dart turns the payload back into a
--  typed `CallException`. Nothing raises except a malformed call that
--  should never happen from our own client.
--
--  ## Error codes (stable; CallApi switches on these)
--
--    NOT_AUTHENTICATED   no JWT
--    CALLS_DISABLED      the feature flag is off
--    ACCOUNT_INACTIVE    caller is banned
--    NOT_ALLOWED         blocked, privacy setting, or not connected
--    ALREADY_IN_CALL     caller is on another call
--    RECIPIENT_BUSY      callee is on another call
--    RATE_LIMITED        too many attempts
--    QUOTA_EXCEEDED      out of daily/monthly minutes
--    CALL_FULL           group call is at max_participants
--    CALL_OVER           the call already ended
--    NOT_A_PARTICIPANT   you are not in this call
--    NOT_ALLOWED_GROUP   not a member of the group
--    INVALID_STATE       transition is not legal from here
--
--  ## Idempotency (§37)
--
--  Every terminal transition takes `FOR UPDATE` on the calls row first
--  and returns early if the call has already ended. `call_finalize` is
--  the ONLY writer of ended_at / end_reason / duration / usage, it is
--  called from seven places, and it is a no-op the second time. The
--  unique partial index on call_events (patch_260) is the backstop if a
--  race ever gets past the lock.
--
--  DEPENDS ON: patch_260 (tables + config), patch_026
--  (check_and_consume_rate_limit), patch_200 (is_blocked_by),
--  patch_118 (are_friends), patch_052 (is_conversation_member /
--  is_conversation_admin), schema.sql (user_is_active), patch_133
--  (is_super_admin).
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  0. Internal helpers. None of these are granted to any client role.
-- ---------------------------------------------------------------------

-- The refusal envelope. See the header for why this is a RETURN value.
CREATE OR REPLACE FUNCTION public.call_error(p_code TEXT, p_message TEXT)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object('error', p_code, 'message', p_message);
$$;

REVOKE ALL ON FUNCTION public.call_error(TEXT, TEXT) FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.call_log_event(
  p_call   UUID,
  p_user   UUID,
  p_event  TEXT,
  p_detail JSONB DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Whitelist. call_events.detail is a diagnostics bag, and a bag with
  -- no lid is how a "let's just log the payload" change ends up storing
  -- SDP (which carries device IP addresses) or worse. Only these keys
  -- survive; anything else the caller passes is dropped silently.
  INSERT INTO public.call_events (call_id, user_id, event, detail)
  VALUES (
    p_call,
    p_user,
    p_event,
    COALESCE(
      (SELECT jsonb_object_agg(k, v)
         FROM jsonb_each(COALESCE(p_detail, '{}'::jsonb)) AS e(k, v)
        WHERE k IN ('reason', 'kind', 'network', 'relayed', 'ice',
                    'participants', 'seconds', 'code', 'platform',
                    'limit', 'used', 'peer_count')),
      '{}'::jsonb)
  )
  -- The unique partial index makes a second 'ended' row an error; an
  -- audit line is never worth failing a hang-up over.
  ON CONFLICT DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  -- Diagnostics must never be able to break a call.
  NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.call_log_event(UUID, UUID, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;


-- Have these two ever actually talked? Used by the "a stranger may not
-- make your phone ring" rule. Mirrors enforce_non_friend_message_cap
-- (patch_118): a stranger gets three messages, and only a reply opens
-- the door further. A ringing phone is a much louder interruption than
-- an unread badge, so it sits behind the same gate, not a looser one.
CREATE OR REPLACE FUNCTION public.call_has_two_way_chat(p_a UUID, p_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.conversations c
     WHERE COALESCE(c.is_group, FALSE) = FALSE
       AND ((c.participant_a_id = p_a AND c.participant_b_id = p_b)
         OR (c.participant_a_id = p_b AND c.participant_b_id = p_a))
       AND EXISTS (SELECT 1 FROM public.messages m
                    WHERE m.conversation_id = c.id AND m.sender_id = p_a)
       AND EXISTS (SELECT 1 FROM public.messages m
                    WHERE m.conversation_id = c.id AND m.sender_id = p_b)
  );
$$;

REVOKE ALL ON FUNCTION public.call_has_two_way_chat(UUID, UUID)
  FROM PUBLIC, anon, authenticated;


-- Are these two in a block relationship, either direction? patch_200
-- made blocking symmetric; this asks the same question about two
-- ARBITRARY members rather than about auth.uid(), which is what group
-- invites need.
CREATE OR REPLACE FUNCTION public.call_blocked_between(p_a UUID, p_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker_id = p_a AND b.blocked_id = p_b)
        OR (b.blocker_id = p_b AND b.blocked_id = p_a));
$$;

REVOKE ALL ON FUNCTION public.call_blocked_between(UUID, UUID)
  FROM PUBLIC, anon, authenticated;


-- May `p_from` make `p_to`'s phone ring? Returns 'ok' or a reason.
--
-- This is the single chokepoint for §23 / §39 / §40. Both directions of
-- blocking, the account state, the member's own "who can message me"
-- setting, and the stranger rule. Group invites go through the block
-- half of it too, so there is no second route to a blocked person.
CREATE OR REPLACE FUNCTION public.call_reachability(p_from UUID, p_to UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_banned  BOOLEAN;
  v_privacy TEXT;
BEGIN
  IF p_from IS NULL OR p_to IS NULL THEN RETURN 'unavailable'; END IF;
  IF p_from = p_to THEN RETURN 'self'; END IF;

  SELECT is_banned, COALESCE(who_can_message, 'everyone')
    INTO v_banned, v_privacy
    FROM public.profiles WHERE id = p_to;

  -- No row = deleted account. Same answer as banned: unavailable. We do
  -- NOT distinguish, because "this account was deleted" told to whoever
  -- asks is itself a disclosure.
  IF NOT FOUND OR v_banned THEN RETURN 'unavailable'; END IF;

  IF public.call_blocked_between(p_from, p_to) THEN RETURN 'blocked'; END IF;

  IF v_privacy = 'nobody' THEN RETURN 'privacy'; END IF;
  IF v_privacy = 'friends' AND NOT public.are_friends(p_from, p_to) THEN
    RETURN 'privacy';
  END IF;

  IF public.call_cfg_bool('call.require_friend_or_reply', TRUE)
     AND NOT public.are_friends(p_from, p_to)
     AND NOT public.call_has_two_way_chat(p_from, p_to)
  THEN
    RETURN 'not_connected';
  END IF;

  RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION public.call_reachability(UUID, UUID)
  FROM PUBLIC, anon, authenticated;


-- How many live calls is this member currently tied up in?
CREATE OR REPLACE FUNCTION public.call_live_count(p_user UUID)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COUNT(*)::INTEGER
    FROM public.call_participants p
    JOIN public.calls c ON c.id = p.call_id
   WHERE p.user_id = p_user
     AND p.status IN ('invited', 'ringing', 'joined')
     AND c.status <> 'ended';
$$;

REVOKE ALL ON FUNCTION public.call_live_count(UUID)
  FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.call_usage_seconds(p_user UUID)
RETURNS TABLE (today_seconds INTEGER, month_seconds INTEGER)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    COALESCE((SELECT seconds FROM public.call_usage_daily
               WHERE user_id = p_user AND day = CURRENT_DATE), 0),
    COALESCE((SELECT SUM(seconds)::INTEGER FROM public.call_usage_daily
               WHERE user_id = p_user
                 AND day >= date_trunc('month', CURRENT_DATE)::date), 0);
$$;

REVOKE ALL ON FUNCTION public.call_usage_seconds(UUID)
  FROM PUBLIC, anon, authenticated;


-- Is this member on an active premium subscription? Read defensively:
-- premium is a separate feature owned by another part of the app, and a
-- change to its schema must never be able to stop calls working. A
-- missing table means "free tier", and the free ceilings are generous
-- enough that this is not a punishment.
CREATE OR REPLACE FUNCTION public.call_is_premium(p_user UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  EXECUTE $q$
    SELECT EXISTS (SELECT 1 FROM public.premium_subscriptions
                    WHERE user_id = $1
                      AND status = 'active'
                      AND (expires_at IS NULL OR expires_at > now()))
  $q$ INTO v_ok USING p_user;
  RETURN COALESCE(v_ok, FALSE);
EXCEPTION WHEN OTHERS THEN
  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.call_is_premium(UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  1. call_snapshot — the shape every RPC returns.
--
--  Defined before its callers on purpose: plpgsql resolves function
--  names at run time, so the order would not break anything, but a file
--  you can read top to bottom is worth the two minutes.
--
--  `room_token` — the Realtime signalling capability (patch_260) — is
--  included ONLY when the viewer's own participant row is live. A
--  member who has left, been removed or declined gets the same JSON
--  with a null token, so a stale client cannot rejoin the channel off a
--  response it captured earlier.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_snapshot(p_call UUID, p_viewer UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_call public.calls%ROWTYPE;
  v_mine TEXT;
BEGIN
  SELECT * INTO v_call FROM public.calls WHERE id = p_call;
  IF NOT FOUND THEN
    RETURN public.call_error('CALL_OVER', 'That call no longer exists.');
  END IF;

  SELECT status INTO v_mine FROM public.call_participants
   WHERE call_id = p_call AND user_id = p_viewer;
  IF v_mine IS NULL THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;

  RETURN jsonb_build_object(
    'id',               v_call.id,
    'kind',             v_call.kind,
    'status',           v_call.status,
    'end_reason',       v_call.end_reason,
    'conversation_id',  v_call.conversation_id,
    'created_by',       v_call.created_by,
    'started_at',       v_call.started_at,
    'connected_at',     v_call.connected_at,
    'ended_at',         v_call.ended_at,
    'ring_expires_at',  v_call.ring_expires_at,
    'hard_expires_at',  v_call.hard_expires_at,
    'max_participants', v_call.max_participants,
    'my_status',        v_mine,
    'room_token',       CASE
                          WHEN v_call.status <> 'ended'
                           AND v_mine IN ('invited', 'ringing', 'joined')
                          THEN v_call.room_token::text
                          ELSE NULL
                        END,
    'participants', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id',   p.user_id,
               'role',      p.role,
               'status',    p.status,
               'muted',     p.muted,
               'joined_at', p.joined_at,
               'name',      COALESCE(NULLIF(trim(pr.full_name), ''), 'Member'),
               'photo_url', pr.profile_photo_url
             ) ORDER BY p.role DESC, p.invited_at)
        FROM public.call_participants p
        LEFT JOIN public.profiles pr ON pr.id = p.user_id
       WHERE p.call_id = p_call), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.call_snapshot(UUID, UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  2. call_finalize — the ONLY place a call ends.
--
--  Idempotent by construction: takes the row lock, returns immediately
--  if already ended. Closes every still-live participant row, computes
--  each leg's billed seconds from server timestamps, folds them into
--  call_usage_daily, and writes exactly one 'ended' event.
--
--  Ringing time is free (§16). A leg's seconds run joined_at → now, and
--  only for legs that actually joined, so a call that never connected
--  bills zero for everyone. That is also why the ATTEMPT ceilings, not
--  the minute quota, are the real defence against call bombing: bombing
--  costs the attacker no minutes at all.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_finalize(p_call UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_call public.calls%ROWTYPE;
  v_now  TIMESTAMPTZ := now();
  v_secs INTEGER;
  r      RECORD;
BEGIN
  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_call.status = 'ended' THEN RETURN; END IF;   -- §37: ends once.

  FOR r IN
    SELECT * FROM public.call_participants
     WHERE call_id = p_call
       AND status IN ('invited', 'ringing', 'joined')
     FOR UPDATE
  LOOP
    IF r.status = 'joined' AND r.joined_at IS NOT NULL THEN
      v_secs := GREATEST(0, EXTRACT(EPOCH FROM (v_now - r.joined_at))::INTEGER);

      UPDATE public.call_participants
         SET status = 'left', left_at = v_now, duration_seconds = v_secs
       WHERE call_id = p_call AND user_id = r.user_id;

      INSERT INTO public.call_usage_daily AS u
        (user_id, day, seconds, group_seconds, calls_answered, relayed_seconds)
      VALUES (
        r.user_id, (v_now AT TIME ZONE 'UTC')::date, v_secs,
        CASE WHEN v_call.kind = 'group' THEN v_secs ELSE 0 END,
        1,
        CASE WHEN r.relayed THEN v_secs ELSE 0 END)
      ON CONFLICT (user_id, day) DO UPDATE
        SET seconds         = u.seconds         + EXCLUDED.seconds,
            group_seconds   = u.group_seconds   + EXCLUDED.group_seconds,
            calls_answered  = u.calls_answered  + EXCLUDED.calls_answered,
            relayed_seconds = u.relayed_seconds + EXCLUDED.relayed_seconds;
    ELSE
      -- Invited or ringing when the call died. Whose fault it was
      -- decides what their row says.
      UPDATE public.call_participants
         SET status = CASE
                        WHEN p_reason = 'busy'     THEN 'busy'
                        WHEN p_reason = 'rejected' THEN 'rejected'
                        ELSE 'missed'
                      END,
             left_at = v_now
       WHERE call_id = p_call AND user_id = r.user_id;
    END IF;
  END LOOP;

  UPDATE public.calls
     SET status           = 'ended',
         end_reason       = p_reason,
         ended_at         = v_now,
         duration_seconds = CASE
                              WHEN connected_at IS NULL THEN 0
                              ELSE GREATEST(0, EXTRACT(EPOCH FROM (v_now - connected_at))::INTEGER)
                            END,
         last_seen_at     = v_now
   WHERE id = p_call;

  PERFORM public.call_log_event(p_call, NULL, 'ended',
    jsonb_build_object('reason', p_reason, 'kind', v_call.kind));

  -- §18: missed-call notification, exactly once per person, and only
  -- for a call that was never answered. The NOT EXISTS is what makes a
  -- double-finalize race unable to produce two rows even though
  -- call_finalize itself is already guarded.
  IF v_call.connected_at IS NULL
     AND p_reason IN ('missed', 'cancelled', 'unreachable', 'stale') THEN
    INSERT INTO public.notifications (user_id, title, body, type,
                                      reference_id, reference_type)
    SELECT p.user_id,
           'Missed call',
           COALESCE(
             (SELECT NULLIF(trim(pr.full_name), '') FROM public.profiles pr
               WHERE pr.id = v_call.created_by),
             'Someone')
           || CASE WHEN v_call.kind = 'group'
                   THEN ' started a group call' ELSE ' called you' END,
           'missed_call',
           p_call::text,
           'call'
      FROM public.call_participants p
     WHERE p.call_id = p_call
       AND p.user_id <> v_call.created_by
       AND p.status = 'missed'
       AND NOT EXISTS (
             SELECT 1 FROM public.notifications n
              WHERE n.user_id = p.user_id
                AND n.reference_type = 'call'
                AND n.reference_id = p_call::text);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.call_finalize(UUID, TEXT)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  3. Pre-flight that does NOT consume anything.
--
--  Split from the consuming half deliberately — see the header. These
--  are the questions whose answer does not depend on how many times you
--  have asked: is the feature on, are you banned, are you already on a
--  call, have your recent calls all gone unanswered, are you out of
--  minutes. Returns NULL when clear, or a refusal envelope.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_preflight(p_user UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today INTEGER;
  v_month INTEGER;
  v_dmax  INTEGER;
  v_mmax  INTEGER;
  v_prem  BOOLEAN;
  v_unans INTEGER;
BEGIN
  IF NOT public.call_cfg_bool('call.enabled', TRUE) THEN
    RETURN public.call_error('CALLS_DISABLED',
      'Calling is temporarily unavailable. Please try again later.');
  END IF;

  IF NOT public.user_is_active() THEN
    RETURN public.call_error('ACCOUNT_INACTIVE',
      'Your account cannot start calls.');
  END IF;

  -- §19 / §31: one call at a time. Call waiting is deliberately not
  -- implemented — a half-working second line is worse than a clean busy.
  IF public.call_live_count(p_user)
       >= public.call_cfg_int('call.max_concurrent_calls', 1) THEN
    RETURN public.call_error('ALREADY_IN_CALL', 'You are already on a call.');
  END IF;

  -- §28: the unanswered ceiling. Counted from the calls table rather
  -- than consumed from the rate ledger, because this one has to be a
  -- QUESTION ("how many of my recent calls went unanswered?"), not a
  -- token that asking spends.
  SELECT COUNT(*)::INTEGER INTO v_unans
    FROM public.calls c
   WHERE c.created_by = p_user
     AND c.started_at > now()
         - make_interval(secs => public.call_cfg_int('call.rate_unanswered_window', 3600))
     AND c.end_reason IN ('rejected', 'missed', 'busy', 'unreachable', 'failed');
  IF v_unans >= public.call_cfg_int('call.rate_unanswered_max', 20) THEN
    RETURN public.call_error('RATE_LIMITED',
      'Too many unanswered calls recently. Please try again later.');
  END IF;

  -- §32: usage quota. Prevents a NEW call once exhausted; never cuts a
  -- call that is already running — the hard per-call ceiling does that,
  -- and it is a different, announced thing.
  v_prem := public.call_is_premium(p_user);
  v_dmax := CASE WHEN v_prem
                 THEN public.call_cfg_int('call.premium_daily_minutes', 360)
                 ELSE public.call_cfg_int('call.free_daily_minutes', 120) END * 60;
  v_mmax := CASE WHEN v_prem
                 THEN public.call_cfg_int('call.premium_monthly_minutes', 4500)
                 ELSE public.call_cfg_int('call.free_monthly_minutes', 1500) END * 60;

  SELECT today_seconds, month_seconds INTO v_today, v_month
    FROM public.call_usage_seconds(p_user);

  IF v_today >= v_dmax THEN
    RETURN public.call_error('QUOTA_EXCEEDED',
      'You have used your call minutes for today. They reset at midnight UTC.');
  END IF;
  IF v_month >= v_mmax THEN
    RETURN public.call_error('QUOTA_EXCEEDED',
      'You have used your call minutes for this month.');
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.call_preflight(UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  4. call_start — place a call.
--
--  `p_kind` = 'direct' (needs p_target) or 'group' (needs
--  p_conversation; p_invitees optionally narrows who gets rung).
--
--  ORDER OF OPERATIONS MATTERS HERE. Cheap, non-consuming checks first;
--  the attempt token is spent only once the call is actually going to
--  be created, and every refusal after that point returns rather than
--  raises so the spend sticks. See the header.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_start(
  p_kind         TEXT,
  p_target       UUID   DEFAULT NULL,
  p_conversation BIGINT DEFAULT NULL,
  p_invitees     UUID[] DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me       UUID := auth.uid();
  v_err      JSONB;
  v_call     UUID;
  v_cap      INTEGER;
  v_ring     INTEGER;
  v_maxmin   INTEGER;
  v_reason   TEXT;
  v_existing UUID;
  v_invited  UUID[] := ARRAY[]::UUID[];
  v_uid      UUID;
  v_is_group BOOLEAN;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;
  IF p_kind NOT IN ('direct', 'group') THEN
    RETURN public.call_error('INVALID_STATE', 'Unknown call type.');
  END IF;

  -- A group that already has a call running is JOINED, not duplicated —
  -- otherwise the group ends up split across two rooms, each half
  -- wondering where everyone is. Checked before the attempt ceiling so
  -- joining an in-progress call is not charged as placing a new one.
  IF p_kind = 'group' AND p_conversation IS NOT NULL THEN
    SELECT id INTO v_existing FROM public.calls
     WHERE conversation_id = p_conversation
       AND kind = 'group'
       AND status <> 'ended'
     ORDER BY started_at DESC LIMIT 1;
    IF v_existing IS NOT NULL THEN
      RETURN public.call_join(v_existing);
    END IF;
  END IF;

  v_err := public.call_preflight(v_me);
  IF v_err IS NOT NULL THEN RETURN v_err; END IF;

  v_ring   := public.call_cfg_int('call.ring_timeout_seconds', 45);
  v_cap    := public.call_cfg_int('call.max_group_participants', 5);
  v_maxmin := CASE WHEN p_kind = 'group'
                   THEN public.call_cfg_int('call.max_group_call_minutes', 90)
                   ELSE public.call_cfg_int('call.max_direct_call_minutes', 120) END;

  -- ================= direct =================
  IF p_kind = 'direct' THEN
    IF p_target IS NULL THEN
      RETURN public.call_error('INVALID_STATE', 'No one to call.');
    END IF;

    v_reason := public.call_reachability(v_me, p_target);
    IF v_reason <> 'ok' THEN
      -- ONE message for every refusal. Telling the caller which of
      -- "they blocked you" / "their privacy setting" / "that account is
      -- gone" applies is a disclosure about the other person, and
      -- blocking in particular must not be detectable.
      RETURN public.call_error('NOT_ALLOWED', 'You can''t call this person.');
    END IF;

    -- §28: the attempt ceiling and the same-recipient ceiling. Spent
    -- here, at the point the call becomes real.
    IF NOT public.check_and_consume_rate_limit(
         v_me::text, 'call_attempt',
         public.call_cfg_int('call.rate_attempts_max', 10),
         public.call_cfg_int('call.rate_attempts_window', 600)) THEN
      RETURN public.call_error('RATE_LIMITED',
        'You have tried to call a lot in a short time. Please wait a few minutes.');
    END IF;

    IF NOT public.check_and_consume_rate_limit(
         v_me::text, 'call_to_' || p_target::text,
         public.call_cfg_int('call.rate_per_recipient_max', 3),
         public.call_cfg_int('call.rate_per_recipient_window', 600)) THEN
      RETURN public.call_error('RATE_LIMITED',
        'You have called this person several times just now. Please give them a moment.');
    END IF;

    INSERT INTO public.calls
      (kind, conversation_id, created_by, max_participants,
       ring_expires_at, hard_expires_at)
    VALUES
      ('direct', p_conversation, v_me, 2,
       now() + make_interval(secs => v_ring),
       now() + make_interval(mins => v_maxmin))
    RETURNING id INTO v_call;

    INSERT INTO public.call_participants (call_id, user_id, role, status, joined_at)
    VALUES (v_call, v_me, 'caller', 'joined', now());

    INSERT INTO public.call_participants (call_id, user_id, role, status)
    VALUES (v_call, p_target, 'callee', 'invited');

    -- §19: they are already on a call. The row is created anyway so
    -- both sides get an honest history entry, then ended immediately as
    -- busy. The caller sees "on another call" instead of a phone that
    -- rings into nothing.
    IF public.call_live_count(p_target) > 0 THEN
      PERFORM public.call_log_event(v_call, v_me, 'created',
        jsonb_build_object('kind', 'direct'));
      PERFORM public.call_finalize(v_call, 'busy');
      RETURN public.call_error('RECIPIENT_BUSY', 'They are on another call.');
    END IF;

    v_invited := ARRAY[p_target];

  -- ================= group =================
  ELSE
    IF p_conversation IS NULL THEN
      RETURN public.call_error('INVALID_STATE', 'No group selected.');
    END IF;

    SELECT COALESCE(is_group, FALSE) INTO v_is_group
      FROM public.conversations WHERE id = p_conversation;
    IF NOT COALESCE(v_is_group, FALSE) THEN
      RETURN public.call_error('NOT_ALLOWED_GROUP', 'That is not a group.');
    END IF;

    -- §25: membership is checked here, never trusted from the client.
    IF NOT public.is_conversation_member(p_conversation) THEN
      RETURN public.call_error('NOT_ALLOWED_GROUP',
        'You are not a member of this group.');
    END IF;

    -- §29: group-call creation and invitation ceilings.
    IF NOT public.check_and_consume_rate_limit(
         v_me::text, 'call_attempt',
         public.call_cfg_int('call.rate_attempts_max', 10),
         public.call_cfg_int('call.rate_attempts_window', 600)) THEN
      RETURN public.call_error('RATE_LIMITED',
        'You have tried to call a lot in a short time. Please wait a few minutes.');
    END IF;

    IF NOT public.check_and_consume_rate_limit(
         v_me::text, 'call_group_create',
         public.call_cfg_int('call.rate_group_create_max', 6),
         public.call_cfg_int('call.rate_group_create_window', 3600)) THEN
      RETURN public.call_error('RATE_LIMITED',
        'You have started several group calls recently. Please wait a while.');
    END IF;

    IF NOT public.check_and_consume_rate_limit(
         v_me::text, 'call_group_invite',
         public.call_cfg_int('call.rate_group_invite_max', 30),
         public.call_cfg_int('call.rate_group_invite_window', 3600)) THEN
      RETURN public.call_error('RATE_LIMITED',
        'You have invited a lot of people to calls recently. Please wait a while.');
    END IF;

    INSERT INTO public.calls
      (kind, conversation_id, created_by, max_participants,
       ring_expires_at, hard_expires_at)
    VALUES
      ('group', p_conversation, v_me, v_cap,
       now() + make_interval(secs => v_ring),
       now() + make_interval(mins => v_maxmin))
    RETURNING id INTO v_call;

    INSERT INTO public.call_participants (call_id, user_id, role, status, joined_at)
    VALUES (v_call, v_me, 'caller', 'joined', now());

    -- Who gets rung. The client's array is a REQUEST, not an
    -- instruction: everyone in it is re-checked against live group
    -- membership and the block rules, and the LIMIT is what makes the
    -- participant cap unforgeable rather than a number the UI respects.
    --
    -- Note what is deliberately NOT applied here: `who_can_message` and
    -- the stranger rule. Inside a group you are already sharing a room
    -- with these people; those two settings govern strangers reaching
    -- you cold. Blocking and account state still apply, and they are
    -- the ones that matter (§39).
    FOR v_uid IN
      SELECT m.user_id
        FROM public.conversation_members m
        JOIN public.profiles pr ON pr.id = m.user_id
       WHERE m.conversation_id = p_conversation
         AND m.left_at IS NULL
         AND m.user_id <> v_me
         AND pr.is_banned = FALSE
         AND (p_invitees IS NULL OR m.user_id = ANY(p_invitees))
         AND NOT public.call_blocked_between(v_me, m.user_id)
       ORDER BY m.joined_at
       LIMIT GREATEST(v_cap - 1, 0)
    LOOP
      INSERT INTO public.call_participants (call_id, user_id, role, status)
      VALUES (v_call, v_uid, 'callee', 'invited')
      ON CONFLICT DO NOTHING;
      v_invited := array_append(v_invited, v_uid);
    END LOOP;

    IF array_length(v_invited, 1) IS NULL THEN
      PERFORM public.call_finalize(v_call, 'unreachable');
      RETURN public.call_error('NOT_ALLOWED',
        'There is no one available to call in this group.');
    END IF;
  END IF;

  INSERT INTO public.call_usage_daily (user_id, day, calls_started)
  VALUES (v_me, (now() AT TIME ZONE 'UTC')::date, 1)
  ON CONFLICT (user_id, day) DO UPDATE
    SET calls_started = public.call_usage_daily.calls_started + 1;

  PERFORM public.call_log_event(v_call, v_me, 'created',
    jsonb_build_object('kind', p_kind,
                       'participants', COALESCE(array_length(v_invited, 1), 0) + 1));

  RETURN public.call_snapshot(v_call, v_me);
END;
$$;


-- ---------------------------------------------------------------------
--  5. The transitions.
-- ---------------------------------------------------------------------

-- The callee's device confirms it is actually alerting. This is what
-- turns "a push was dispatched" into "their phone is ringing" for the
-- caller — FCM queues for offline devices, so dispatch proves nothing.
CREATE OR REPLACE FUNCTION public.call_ring_ack(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me UUID := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;
  UPDATE public.call_participants
     SET status = 'ringing', ringing_at = now(), last_seen_at = now()
   WHERE call_id = p_call AND user_id = v_me AND status = 'invited';
  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


CREATE OR REPLACE FUNCTION public.call_accept(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me     UUID := auth.uid();
  v_call   public.calls%ROWTYPE;
  v_mine   TEXT;
  v_joined INTEGER;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND OR v_call.status = 'ended' THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;

  SELECT status INTO v_mine FROM public.call_participants
   WHERE call_id = p_call AND user_id = v_me FOR UPDATE;
  IF v_mine IS NULL THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;

  -- Accepting twice must be a no-op, not an error. It happens for real:
  -- the in-app incoming screen and the CallKit / CallStyle sheet can
  -- both be showing, and a fast tap hits both.
  IF v_mine = 'joined' THEN
    RETURN public.call_snapshot(p_call, v_me);
  END IF;
  IF v_mine NOT IN ('invited', 'ringing') THEN
    RETURN public.call_error('INVALID_STATE', 'That call is no longer available.');
  END IF;

  IF public.call_live_count(v_me)
       >= public.call_cfg_int('call.max_concurrent_calls', 1) THEN
    RETURN public.call_error('ALREADY_IN_CALL', 'You are already on a call.');
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_joined FROM public.call_participants
   WHERE call_id = p_call AND status = 'joined';
  IF v_joined >= v_call.max_participants THEN
    RETURN public.call_error('CALL_FULL', 'This call is full.');
  END IF;

  UPDATE public.call_participants
     SET status = 'joined', joined_at = now(), last_seen_at = now()
   WHERE call_id = p_call AND user_id = v_me;

  UPDATE public.calls
     SET status = 'active',
         -- §16: the billing clock starts HERE, the first time two people
         -- are actually in the room together. Never on invite, never on
         -- ring. COALESCE keeps a later joiner from resetting it.
         connected_at = COALESCE(connected_at,
                          CASE WHEN v_joined + 1 >= 2 THEN now() ELSE NULL END),
         peak_participants = GREATEST(peak_participants, (v_joined + 1)::SMALLINT),
         last_seen_at = now()
   WHERE id = p_call;

  PERFORM public.call_log_event(p_call, v_me, 'accepted',
    jsonb_build_object('peer_count', v_joined + 1));

  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


CREATE OR REPLACE FUNCTION public.call_reject(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_call public.calls%ROWTYPE;
  v_mine TEXT;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;

  SELECT status INTO v_mine FROM public.call_participants
   WHERE call_id = p_call AND user_id = v_me;
  IF v_mine IS NULL THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;

  IF v_call.status = 'ended' THEN
    RETURN public.call_snapshot(p_call, v_me);
  END IF;

  IF v_mine IN ('invited', 'ringing') THEN
    UPDATE public.call_participants
       SET status = 'rejected', left_at = now()
     WHERE call_id = p_call AND user_id = v_me;
    PERFORM public.call_log_event(p_call, v_me, 'rejected', '{}'::jsonb);
  END IF;

  -- A 1:1 call with nobody left to answer is over. A group call carries
  -- on without the person who declined.
  IF v_call.kind = 'direct' THEN
    PERFORM public.call_finalize(p_call, 'rejected');
  END IF;

  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


-- The caller gives up before anyone answers.
CREATE OR REPLACE FUNCTION public.call_cancel(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_call public.calls%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;
  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;
  IF v_call.created_by <> v_me THEN
    RETURN public.call_error('NOT_ALLOWED', 'Only the caller can cancel.');
  END IF;
  IF v_call.status <> 'ended' THEN
    PERFORM public.call_finalize(p_call, 'cancelled');
  END IF;
  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


-- Leave a call without ending it for everyone (§4). In a 1:1 there is
-- no such thing, so leaving finalises. In a group the room lives on
-- until fewer than two people are left in it.
CREATE OR REPLACE FUNCTION public.call_leave(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_call public.calls%ROWTYPE;
  v_p    public.call_participants%ROWTYPE;
  v_secs INTEGER := 0;
  v_left INTEGER;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;

  SELECT * INTO v_p FROM public.call_participants
   WHERE call_id = p_call AND user_id = v_me FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;

  IF v_call.status = 'ended' THEN
    RETURN public.call_snapshot(p_call, v_me);
  END IF;

  IF v_p.status = 'joined' AND v_p.joined_at IS NOT NULL THEN
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_p.joined_at))::INTEGER);
    UPDATE public.call_participants
       SET status = 'left', left_at = now(), duration_seconds = v_secs
     WHERE call_id = p_call AND user_id = v_me;

    INSERT INTO public.call_usage_daily AS u
      (user_id, day, seconds, group_seconds, calls_answered, relayed_seconds)
    VALUES (v_me, (now() AT TIME ZONE 'UTC')::date, v_secs,
            CASE WHEN v_call.kind = 'group' THEN v_secs ELSE 0 END, 1,
            CASE WHEN v_p.relayed THEN v_secs ELSE 0 END)
    ON CONFLICT (user_id, day) DO UPDATE
      SET seconds         = u.seconds         + EXCLUDED.seconds,
          group_seconds   = u.group_seconds   + EXCLUDED.group_seconds,
          calls_answered  = u.calls_answered  + EXCLUDED.calls_answered,
          relayed_seconds = u.relayed_seconds + EXCLUDED.relayed_seconds;
  ELSE
    UPDATE public.call_participants
       SET status = 'left', left_at = now()
     WHERE call_id = p_call AND user_id = v_me;
  END IF;

  PERFORM public.call_log_event(p_call, v_me, 'left',
    jsonb_build_object('seconds', v_secs));

  SELECT COUNT(*)::INTEGER INTO v_left FROM public.call_participants
   WHERE call_id = p_call AND status IN ('joined', 'invited', 'ringing');

  IF v_call.kind = 'direct' OR v_left < 2 THEN
    PERFORM public.call_finalize(
      p_call,
      CASE WHEN v_call.connected_at IS NOT NULL THEN 'completed'
           WHEN v_call.created_by = v_me        THEN 'cancelled'
           ELSE 'missed' END);
  END IF;

  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


-- End the call for EVERYONE. Creator, a group admin, or a super admin.
CREATE OR REPLACE FUNCTION public.call_end(p_call UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_call public.calls%ROWTYPE;
  v_ok   BOOLEAN := FALSE;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;

  IF v_call.created_by = v_me THEN
    v_ok := TRUE;
  ELSIF v_call.conversation_id IS NOT NULL
        AND public.is_conversation_admin(v_call.conversation_id) THEN
    v_ok := TRUE;
  ELSIF public.is_super_admin() THEN
    v_ok := TRUE;
  END IF;

  IF NOT v_ok THEN
    RETURN public.call_error('NOT_ALLOWED',
      'Only the host can end the call for everyone.');
  END IF;

  -- The client may suggest a reason, but only from a safe list. The
  -- interesting ones ('completed', 'stale', 'quota', 'max_duration')
  -- are the server's to assign.
  IF v_call.status <> 'ended' THEN
    PERFORM public.call_finalize(
      p_call,
      CASE WHEN p_reason IN ('completed', 'cancelled', 'failed') THEN p_reason
           WHEN v_call.connected_at IS NOT NULL THEN 'completed'
           ELSE 'cancelled' END);
  END IF;

  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


-- Join a group call already in progress (§4 "joining an existing group
-- call") — from the group info screen, the Calls tab, or call_start.
CREATE OR REPLACE FUNCTION public.call_join(p_call UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me     UUID := auth.uid();
  v_err    JSONB;
  v_call   public.calls%ROWTYPE;
  v_mine   TEXT;
  v_joined INTEGER;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND OR v_call.status = 'ended' THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;

  SELECT status INTO v_mine FROM public.call_participants
   WHERE call_id = p_call AND user_id = v_me;

  -- §25: someone who was REMOVED does not get back in.
  IF v_mine = 'removed' THEN
    RETURN public.call_error('NOT_ALLOWED', 'You were removed from this call.');
  END IF;

  -- Already invited: this is just an accept, and it must not be charged
  -- as a join attempt or the ring→accept path would burn the ceiling.
  IF v_mine IN ('invited', 'ringing', 'joined') THEN
    RETURN public.call_accept(p_call);
  END IF;

  -- From here on this is a genuine uninvited join.
  -- §29: repeated leave/join cycling is its own abuse shape.
  IF NOT public.check_and_consume_rate_limit(
       v_me::text, 'call_join',
       public.call_cfg_int('call.rate_join_max', 10),
       public.call_cfg_int('call.rate_join_window', 60)) THEN
    RETURN public.call_error('RATE_LIMITED',
      'Too many join attempts. Please wait a moment.');
  END IF;

  IF v_call.kind <> 'group' OR v_call.conversation_id IS NULL THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;
  IF NOT public.is_conversation_member(v_call.conversation_id) THEN
    RETURN public.call_error('NOT_ALLOWED_GROUP',
      'You are not a member of this group.');
  END IF;

  -- §39: cannot join a room someone you have blocked is sitting in.
  IF EXISTS (
       SELECT 1 FROM public.call_participants p
        WHERE p.call_id = p_call
          AND p.status = 'joined'
          AND public.call_blocked_between(v_me, p.user_id)) THEN
    RETURN public.call_error('NOT_ALLOWED', 'You can''t join this call.');
  END IF;

  v_err := public.call_preflight(v_me);
  IF v_err IS NOT NULL THEN RETURN v_err; END IF;

  SELECT COUNT(*)::INTEGER INTO v_joined FROM public.call_participants
   WHERE call_id = p_call AND status = 'joined';
  IF v_joined >= v_call.max_participants THEN
    RETURN public.call_error('CALL_FULL', 'This call is full.');
  END IF;

  INSERT INTO public.call_participants (call_id, user_id, role, status)
  VALUES (p_call, v_me, 'callee', 'invited')
  ON CONFLICT DO NOTHING;

  RETURN public.call_accept(p_call);
END;
$$;


-- Host removes someone from a group call.
CREATE OR REPLACE FUNCTION public.call_remove_participant(p_call UUID, p_user UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_call public.calls%ROWTYPE;
  v_ok   BOOLEAN := FALSE;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;
  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND OR v_call.status = 'ended' THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;
  IF v_call.kind <> 'group' THEN
    RETURN public.call_error('INVALID_STATE', 'Not a group call.');
  END IF;
  IF p_user = v_me THEN
    RETURN public.call_leave(p_call);
  END IF;

  IF v_call.created_by = v_me THEN v_ok := TRUE;
  ELSIF v_call.conversation_id IS NOT NULL
        AND public.is_conversation_admin(v_call.conversation_id) THEN v_ok := TRUE;
  ELSIF public.is_super_admin() THEN v_ok := TRUE;
  END IF;
  IF NOT v_ok THEN
    RETURN public.call_error('NOT_ALLOWED', 'Only the host can remove people.');
  END IF;

  UPDATE public.call_participants
     SET status = 'removed', left_at = now(),
         duration_seconds = CASE
           WHEN joined_at IS NOT NULL
           THEN GREATEST(0, EXTRACT(EPOCH FROM (now() - joined_at))::INTEGER)
           ELSE duration_seconds END
   WHERE call_id = p_call AND user_id = p_user
     AND status IN ('invited', 'ringing', 'joined');

  PERFORM public.call_log_event(p_call, p_user, 'removed', '{}'::jsonb);
  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


-- Liveness + the mute/network mirror. The client calls this every
-- `call.heartbeat_seconds`; the janitor (patch_263) reads last_seen_at.
--
-- Rate-limited by TIME rather than by a counter: a heartbeat arriving
-- sooner than half the configured interval, with nothing new to say, is
-- answered without writing. A client cannot turn the liveness channel
-- into a write flood however hard it tries, and a well-behaved client
-- never notices the floor.
CREATE OR REPLACE FUNCTION public.call_heartbeat(
  p_call    UUID,
  p_muted   BOOLEAN DEFAULT NULL,
  p_network TEXT    DEFAULT NULL,
  p_relayed BOOLEAN DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_last TIMESTAMPTZ;
  v_min  INTEGER := GREATEST(1, public.call_cfg_int('call.heartbeat_seconds', 15) / 2);
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT last_seen_at INTO v_last FROM public.call_participants
   WHERE call_id = p_call AND user_id = v_me;
  IF NOT FOUND THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;

  IF v_last > now() - make_interval(secs => v_min) AND p_muted IS NULL THEN
    RETURN public.call_snapshot(p_call, v_me);
  END IF;

  UPDATE public.call_participants
     SET last_seen_at = now(),
         muted   = COALESCE(p_muted, muted),
         network = COALESCE(
                     CASE WHEN p_network IN ('wifi', 'mobile', 'other')
                          THEN p_network ELSE NULL END, network),
         relayed = COALESCE(p_relayed, relayed)
   WHERE call_id = p_call AND user_id = v_me;

  UPDATE public.calls SET last_seen_at = now()
   WHERE id = p_call AND status <> 'ended';

  RETURN public.call_snapshot(p_call, v_me);
END;
$$;


-- What call am I in right now, if any? Called on cold start and on
-- every resume. This is what stops a ghost call surviving a force-quit:
-- the app asks the server instead of trusting whatever was in memory.
CREATE OR REPLACE FUNCTION public.call_current()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_me   UUID := auth.uid();
  v_call UUID;
BEGIN
  IF v_me IS NULL THEN RETURN 'null'::jsonb; END IF;
  SELECT c.id INTO v_call
    FROM public.calls c
    JOIN public.call_participants p ON p.call_id = c.id AND p.user_id = v_me
   WHERE c.status <> 'ended'
     AND p.status IN ('invited', 'ringing', 'joined')
   ORDER BY c.started_at DESC LIMIT 1;
  IF v_call IS NULL THEN RETURN 'null'::jsonb; END IF;
  RETURN public.call_snapshot(v_call, v_me);
END;
$$;


-- May this member be handed TURN credentials right now? The
-- call-ice-servers Edge Function calls this WITH THE MEMBER'S OWN JWT
-- before minting anything, so TURN cannot be farmed by anyone who is
-- not currently in a live call (§38, "TURN credential abuse").
CREATE OR REPLACE FUNCTION public.call_may_use_turn(p_call UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me UUID := auth.uid();
BEGIN
  IF v_me IS NULL THEN RETURN FALSE; END IF;

  IF NOT EXISTS (
       SELECT 1 FROM public.call_participants p
         JOIN public.calls c ON c.id = p.call_id
        WHERE p.call_id = p_call
          AND p.user_id = v_me
          AND c.status <> 'ended'
          AND p.status IN ('invited', 'ringing', 'joined')) THEN
    RETURN FALSE;
  END IF;

  -- Consumed only once the request is legitimate, so probing cannot
  -- exhaust a member's own budget.
  RETURN public.check_and_consume_rate_limit(
    v_me::text, 'call_ice',
    public.call_cfg_int('call.rate_ice_max', 30),
    public.call_cfg_int('call.rate_ice_window', 600));
END;
$$;


-- Where to ring this member. Written by the app on launch and on token
-- refresh. `user_call_devices` has no SELECT policy at all, so this RPC
-- is the only write path and the service role is the only reader.
CREATE OR REPLACE FUNCTION public.call_register_device(
  p_platform   TEXT,
  p_voip_token TEXT DEFAULT NULL,
  p_push_token TEXT DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me UUID := auth.uid();
BEGIN
  IF v_me IS NULL THEN RETURN; END IF;
  IF p_platform NOT IN ('android', 'ios') THEN RETURN; END IF;

  INSERT INTO public.user_call_devices
    (user_id, platform, voip_token, push_token, updated_at)
  VALUES
    (v_me, p_platform, NULLIF(trim(p_voip_token), ''),
     NULLIF(trim(p_push_token), ''), now())
  ON CONFLICT (user_id, platform) DO UPDATE
    SET voip_token = COALESCE(EXCLUDED.voip_token, public.user_call_devices.voip_token),
        push_token = COALESCE(EXCLUDED.push_token, public.user_call_devices.push_token),
        updated_at = now();
END;
$$;


-- Sign-out. Drops the tokens so a device that is no longer signed in
-- stops receiving call pushes for this account.
CREATE OR REPLACE FUNCTION public.call_forget_device(p_platform TEXT DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me UUID := auth.uid();
BEGIN
  IF v_me IS NULL THEN RETURN; END IF;
  DELETE FROM public.user_call_devices
   WHERE user_id = v_me
     AND (p_platform IS NULL OR platform = p_platform);
END;
$$;


-- ---------------------------------------------------------------------
--  6. call_history — the Calls tab.
--
--  §17: strictly my own calls. The other people on each call are
--  included because they are the point of the row, but nobody can ask
--  for anyone else's history — there is no user parameter, and
--  auth.uid() is the only identity in the query.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_history(
  p_limit  INTEGER     DEFAULT 40,
  p_before TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.started_at DESC), '[]'::jsonb)
    FROM (
      SELECT c.id,
             c.kind,
             c.status,
             c.end_reason,
             c.conversation_id,
             c.created_by,
             c.started_at,
             c.connected_at,
             c.ended_at,
             c.duration_seconds,
             (c.created_by = auth.uid()) AS outgoing,
             me.status                   AS my_status,
             me.duration_seconds         AS my_seconds,
             (SELECT jsonb_agg(jsonb_build_object(
                       'user_id',   p2.user_id,
                       'status',    p2.status,
                       'name',      COALESCE(NULLIF(trim(pr.full_name), ''), 'Member'),
                       'photo_url', pr.profile_photo_url))
                FROM public.call_participants p2
                LEFT JOIN public.profiles pr ON pr.id = p2.user_id
               WHERE p2.call_id = c.id AND p2.user_id <> auth.uid()) AS others,
             (SELECT COALESCE(NULLIF(trim(cv.name), ''), 'Group')
                FROM public.conversations cv WHERE cv.id = c.conversation_id) AS group_name
        FROM public.call_participants me
        JOIN public.calls c ON c.id = me.call_id
       WHERE me.user_id = auth.uid()
         AND (p_before IS NULL OR c.started_at < p_before)
       ORDER BY c.started_at DESC
       LIMIT LEAST(GREATEST(COALESCE(p_limit, 40), 1), 100)
    ) x;
$$;


-- Clear MY call log. Removes my own participant rows for calls that
-- have ENDED — nothing the other person sees changes, because history
-- is reconstructed per participant rather than read from a shared list.
CREATE OR REPLACE FUNCTION public.call_history_clear(p_call UUID DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me UUID := auth.uid();
BEGIN
  IF v_me IS NULL THEN RETURN; END IF;
  DELETE FROM public.call_participants p
   USING public.calls c
   WHERE p.call_id = c.id
     AND p.user_id = v_me
     AND c.status = 'ended'
     AND (p_call IS NULL OR p.call_id = p_call);
END;
$$;


-- What the app shows on the Calls tab header: minutes used and the
-- ceiling in force for THIS member (free vs premium).
CREATE OR REPLACE FUNCTION public.call_my_usage()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_me    UUID := auth.uid();
  v_today INTEGER;
  v_month INTEGER;
  v_prem  BOOLEAN;
BEGIN
  IF v_me IS NULL THEN RETURN 'null'::jsonb; END IF;
  SELECT today_seconds, month_seconds INTO v_today, v_month
    FROM public.call_usage_seconds(v_me);
  v_prem := public.call_is_premium(v_me);
  RETURN jsonb_build_object(
    'today_seconds',  v_today,
    'month_seconds',  v_month,
    'daily_limit_seconds', (CASE WHEN v_prem
        THEN public.call_cfg_int('call.premium_daily_minutes', 360)
        ELSE public.call_cfg_int('call.free_daily_minutes', 120) END) * 60,
    'monthly_limit_seconds', (CASE WHEN v_prem
        THEN public.call_cfg_int('call.premium_monthly_minutes', 4500)
        ELSE public.call_cfg_int('call.free_monthly_minutes', 1500) END) * 60,
    'premium', v_prem);
END;
$$;


-- ---------------------------------------------------------------------
--  7. Grants. `authenticated` only — never anon (patch_199's lesson).
-- ---------------------------------------------------------------------
DO $$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'call_start(text,uuid,bigint,uuid[])',
    'call_ring_ack(uuid)',
    'call_accept(uuid)',
    'call_reject(uuid)',
    'call_cancel(uuid)',
    'call_leave(uuid)',
    'call_end(uuid,text)',
    'call_join(uuid)',
    'call_remove_participant(uuid,uuid)',
    'call_heartbeat(uuid,boolean,text,boolean)',
    'call_current()',
    'call_may_use_turn(uuid)',
    'call_register_device(text,text,text)',
    'call_forget_device(text)',
    'call_history(integer,timestamptz)',
    'call_history_clear(uuid)',
    'call_my_usage()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', fn);
  END LOOP;
END;
$$;


-- =====================================================================
--  VERIFY
--
--    -- 17 client RPCs, and anon holds none of them:
--    SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon
--      FROM pg_proc p
--     WHERE p.pronamespace = 'public'::regnamespace
--       AND p.proname LIKE 'call\_%'
--       AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
--     ORDER BY 1;
--    -- expect 17 rows, `anon` false on every one
--
--    -- the internal helpers must be reachable by NOBODY:
--    SELECT p.proname
--      FROM pg_proc p
--     WHERE p.pronamespace = 'public'::regnamespace
--       AND p.proname IN ('call_finalize','call_preflight','call_snapshot',
--                         'call_reachability','call_log_event','call_error',
--                         'call_live_count','call_is_premium',
--                         'call_blocked_between','call_has_two_way_chat',
--                         'call_usage_seconds')
--       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
--    -- expect 0 rows
--
--    -- calling yourself is refused (run as a signed-in member):
--    -- SELECT public.call_start('direct', auth.uid());
--    -- -> {"error": "NOT_ALLOWED", ...}
-- =====================================================================
