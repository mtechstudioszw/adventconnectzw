-- =====================================================================
--  PATCH 262 — Realtime signalling authorisation for calls
--
--  patch_260 gave every call a random `room_token` and made the
--  Realtime topic `call:<room_token>`. That is a capability: 122 bits
--  of entropy, handed out only by call_snapshot and only to a live
--  participant. This patch is the SECOND lock — the one that holds even
--  if a token leaks.
--
--  ## What this actually gates
--
--  Supabase Realtime has two channel modes. A PUBLIC channel is not
--  RLS-checked at all: any signed-in client that knows the topic name
--  joins it. A PRIVATE channel (`config: { private: true }` on the
--  client) is authorised against RLS policies on `realtime.messages`
--  before the join is accepted, and again on every message sent.
--
--  The call client joins PRIVATELY (see CallSignaling in
--  lib/services/calls/call_signaling.dart). These policies are what
--  that join is checked against. Without them a private join is refused
--  outright — RLS with no permissive policy denies everything — so if
--  calling suddenly cannot connect, THIS patch not being applied is the
--  first thing to check.
--
--  ## Why this does not disturb the rest of the app
--
--  The existing realtime users — `online_users` presence, the typing
--  channels, `quiz_match:*` — all join PUBLICLY, and a public join
--  never consults `realtime.messages` RLS. Adding policies here
--  therefore cannot change their behaviour in either direction. They
--  are untouched on purpose: converting them would be a separate,
--  riskier change with nothing to do with calling.
--
--  ## What a participant can and cannot do
--
--  A member who is invited, ringing or joined on the call that owns the
--  token may read and write that topic. The moment their participant
--  row goes to left / rejected / missed / removed, or the call ends,
--  both halves stop — so a client that captured a token cannot sit in
--  the room afterwards and listen. That is checked per message, not
--  once at join, which is what makes a mid-call removal actually take
--  effect (§4, "participant removal where appropriate").
--
--  ## What crosses this channel
--
--  SDP offers/answers, ICE candidates, mute flags, and speaking
--  indicators. Never audio — the media is a direct WebRTC stream and
--  does not pass through Supabase at all.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Topic → authorisation
--
--  SECURITY DEFINER because it reads `calls` and `call_participants`,
--  both of which have RLS of their own; evaluating one policy inside
--  another is exactly the recursion patch_052 avoided with
--  is_conversation_member.
--
--  Parsing is defensive. `realtime.topic()` is a client-supplied string,
--  so it is length-checked and cast inside an exception block: a topic
--  of `call:` followed by junk must return FALSE, not raise, because a
--  raise inside an RLS policy surfaces as a confusing 500 rather than a
--  clean refusal.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_topic_access(p_topic TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $fn$
DECLARE
  v_token UUID;
BEGIN
  IF auth.uid() IS NULL THEN RETURN FALSE; END IF;
  IF p_topic IS NULL OR p_topic !~ '^call:[0-9a-fA-F-]{36}$' THEN
    RETURN FALSE;
  END IF;

  BEGIN
    v_token := substring(p_topic FROM 6)::UUID;
  EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
  END;

  RETURN EXISTS (
    SELECT 1
      FROM public.calls c
      JOIN public.call_participants p ON p.call_id = c.id
     WHERE c.room_token = v_token
       AND p.user_id = auth.uid()
       AND c.status <> 'ended'
       AND p.status IN ('invited', 'ringing', 'joined')
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_topic_access(TEXT) FROM PUBLIC, anon;
-- `authenticated` needs EXECUTE because the policy below is evaluated
-- as the requesting role.
GRANT EXECUTE ON FUNCTION public.call_topic_access(TEXT) TO authenticated;


-- ---------------------------------------------------------------------
--  2. Policies on realtime.messages
--
--  Scoped to `call:` topics ONLY. Every policy is `AND`-ed with the
--  topic shape first, so nothing here can widen access to any other
--  channel in the project, now or later.
--
--  Both `broadcast` (SDP/ICE/mute) and `presence` (who is actually in
--  the room right now) are allowed: the participant grid reads presence
--  to notice a phone that vanished before its heartbeat lapsed.
-- ---------------------------------------------------------------------
DO $do$
BEGIN
  -- Receiving.
  DROP POLICY IF EXISTS call_topic_read ON realtime.messages;
  CREATE POLICY call_topic_read ON realtime.messages
    FOR SELECT TO authenticated
    USING (
      realtime.messages.extension IN ('broadcast', 'presence')
      AND public.call_topic_access(realtime.topic())
    );

  -- Sending. Same predicate — there is deliberately no asymmetry, since
  -- a listener who may not speak has no use for a signalling channel.
  DROP POLICY IF EXISTS call_topic_write ON realtime.messages;
  CREATE POLICY call_topic_write ON realtime.messages
    FOR INSERT TO authenticated
    WITH CHECK (
      realtime.messages.extension IN ('broadcast', 'presence')
      AND public.call_topic_access(realtime.topic())
    );
EXCEPTION WHEN insufficient_privilege THEN
  RAISE EXCEPTION
    'patch_262 could not create policies on realtime.messages: %. '
    'Run this patch as the `postgres` role (the Management API query '
    'endpoint does). Calling cannot connect without these.', SQLERRM;
END;
$do$;


-- =====================================================================
--  VERIFY (run these after applying; read the output)
--
--    SELECT polname FROM pg_policy
--     WHERE polrelid = 'realtime.messages'::regclass
--     ORDER BY 1;
--    -- expect call_topic_read and call_topic_write
--
--    -- a junk topic must be refused, not error:
--    SELECT public.call_topic_access('call:not-a-uuid');   -- false
--    SELECT public.call_topic_access('online_users');      -- false
--    SELECT public.call_topic_access(NULL);                -- false
--
--    -- and anon must not even be able to ask:
--    SELECT has_function_privilege('anon',
--             'public.call_topic_access(text)', 'EXECUTE');  -- false
-- =====================================================================
