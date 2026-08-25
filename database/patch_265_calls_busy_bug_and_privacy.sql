-- =====================================================================
--  PATCH 265 — calling: the busy bug, and a "who can call me" setting
--
--  ## 1. THE BUSY BUG (every direct call was refused)
--
--  Production evidence, 25 Aug 2026: NINE calls placed by four different
--  members across three different pairs. All nine ended `busy`. Not one
--  call in the history of this feature has ever rung.
--
--  `call_start` does this, in this order:
--
--      INSERT ... (v_call, p_target, 'callee', 'invited');   -- <= here
--      IF public.call_live_count(p_target) > 0 THEN
--        ... RETURN call_error('RECIPIENT_BUSY', ...)
--
--  and `call_live_count` counts participant rows whose status is one of
--  ('invited','ringing','joined') on a call that is not ended. The row
--  it counts is THE ONE THE LINE ABOVE JUST INSERTED. The check is
--  reading its own write, so it is true unconditionally, for everybody,
--  every time.
--
--  The fix is to exclude the call being created. Done as a new optional
--  parameter rather than by moving the INSERT, because the ordering is
--  deliberate: the row exists before the check so that a genuinely busy
--  callee still gets an honest "missed call" in their history. Moving
--  the INSERT would fix the symptom and quietly delete that behaviour.
--
--  `call_live_count(uuid)` keeps its old signature and delegates, so
--  nothing else that calls it has to change.
--
--  ## 2. WHO MAY RING ME
--
--  `call_reachability` gated calls on `profiles.who_can_message`, i.e.
--  the CHAT privacy setting. That is wrong in both directions: someone
--  happy to receive messages from anyone is not thereby agreeing to let
--  strangers make their phone ring at 3am, and someone who has locked
--  chat down to friends may still want their church elder to be able to
--  call them.
--
--  So calling gets its own setting, mirroring the chat one exactly:
--  'everyone' | 'friends' | 'nobody'.
--
--  **The default is 'friends', not 'everyone'**, and that is the
--  founder's instruction ("when you not friends don't allow calling").
--  It is also the safer default to roll out: a ringing phone is a far
--  louder interruption than an unread badge, and a default that is too
--  tight annoys people who can fix it in Settings, while one that is
--  too loose hands every member's phone to 252 strangers.
--
--  `call.require_friend_or_reply` stays as an emergency global floor but
--  is now only consulted for members who have NOT chosen 'everyone' —
--  a member who explicitly opts into calls from anyone should get them.
--
--  ## THE profiles CHECKLIST (CLAUDE.md — read it before touching this)
--
--  1. Privilege trigger: `who_can_call` is a preference, not a
--     privilege. `profiles_block_privilege_self_grant()` snaps back
--     premium/super_admin/verified/banned/business only, and must NOT
--     learn about this column — a member is supposed to set it.
--  2. GRANTS: `authenticated` has NO table-level SELECT on profiles, it
--     reads through per-column grants. A new column with no grant is
--     invisible, which is exactly how the chat privacy screen shipped
--     broken for everyone (patch_192). SELECT + UPDATE granted below.
--  3. No table-level SELECT exists, so no REVOKE-ordering trap here.
--  4. No DELETE trigger touched.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. call_live_count, with an exclusion
--
--  ONE function with a defaulted second parameter, NOT two overloads.
--
--  That distinction cost a round trip to production. The first cut of
--  this patch kept a 1-arg version alongside a 2-arg version whose
--  second parameter had a DEFAULT — which makes `call_live_count(uuid)`
--  ambiguous, and Postgres refuses it with "function call_live_count
--  (uuid) is not unique". `call_preflight` and the sweeper both call the
--  1-arg form, so the fix for the busy bug would have broken calling in
--  a new way: every call erroring instead of every call reporting busy.
--
--  A defaulted parameter already serves both call shapes. The 1-arg
--  overload is therefore dropped, and must not be reintroduced.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.call_live_count(UUID);

CREATE OR REPLACE FUNCTION public.call_live_count(
  p_user    UUID,
  p_exclude UUID DEFAULT NULL
)
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
     AND c.status <> 'ended'
     AND (p_exclude IS NULL OR c.id <> p_exclude);
$$;

REVOKE ALL ON FUNCTION public.call_live_count(UUID, UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  2. who_can_call
-- ---------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS who_can_call TEXT NOT NULL DEFAULT 'friends';

DO $$
BEGIN
  ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_who_can_call_chk
    CHECK (who_can_call IN ('everyone', 'friends', 'nobody'));
EXCEPTION WHEN duplicate_object THEN
  NULL;
END;
$$;

-- Point 2 of the checklist. Without these the column is invisible to the
-- app and the Settings toggle silently never loads — the patch_192 bug,
-- repeated.
GRANT SELECT (who_can_call) ON public.profiles TO authenticated;
GRANT UPDATE (who_can_call) ON public.profiles TO authenticated;


-- ---------------------------------------------------------------------
--  3. call_reachability reads the CALL setting, not the chat one
-- ---------------------------------------------------------------------
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

  SELECT is_banned, COALESCE(who_can_call, 'friends')
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

  -- The global floor, and note what it does NOT apply to: a member who
  -- has explicitly set 'everyone' has opted into calls from people they
  -- have never spoken to, and overriding that would make the setting a
  -- lie. For everyone else it is the same stranger rule chat uses.
  IF v_privacy <> 'everyone'
     AND public.call_cfg_bool('call.require_friend_or_reply', TRUE)
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


-- ---------------------------------------------------------------------
--  4. call_start: pass the exclusion
--
--  Only the direct branch needs it — the group branch never ran a busy
--  check (joining an in-progress group call is the intended behaviour,
--  not a collision).
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

    -- THE FIX. Excluding v_call is what makes this a question about the
    -- callee's OTHER calls rather than about the row three lines up.
    -- The row is still created first, on purpose, so a genuinely busy
    -- callee gets an honest missed-call entry.
    IF public.call_live_count(p_target, v_call) > 0 THEN
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

    IF NOT public.is_conversation_member(p_conversation) THEN
      RETURN public.call_error('NOT_ALLOWED_GROUP',
        'You are not a member of this group.');
    END IF;

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

    -- Inside a group you are already sharing a room with these people,
    -- so who_can_call (a rule about strangers reaching you cold) does
    -- not apply. Blocking and account state still do.
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

REVOKE ALL ON FUNCTION public.call_start(TEXT, UUID, BIGINT, UUID[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.call_start(TEXT, UUID, BIGINT, UUID[])
  TO authenticated;


-- =====================================================================
--  VERIFY
--
--    -- 1. The busy bug is gone. Two members with no live calls:
--    --    call_live_count(x, <a call they are in>) must be 0.
--    SELECT public.call_live_count(
--             'd88e8287-d3d9-4497-b6bb-826a6793fcc5'::uuid) AS live_now;
--    -- expect 0
--
--    -- 2. The column exists, is constrained, and is READABLE:
--    SELECT column_name, column_default, is_nullable
--      FROM information_schema.columns
--     WHERE table_schema='public' AND table_name='profiles'
--       AND column_name='who_can_call';
--
--    SELECT privilege_type FROM information_schema.column_privileges
--     WHERE table_schema='public' AND table_name='profiles'
--       AND column_name='who_can_call' AND grantee='authenticated'
--     ORDER BY 1;
--    -- expect SELECT and UPDATE. If SELECT is missing the Settings
--    -- screen will silently never load — that is the patch_192 bug.
--
--    -- 3. Nobody's calling is broken by the new default:
--    SELECT who_can_call, count(*) FROM public.profiles GROUP BY 1;
-- =====================================================================
