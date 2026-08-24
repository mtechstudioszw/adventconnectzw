-- =====================================================================
--  PATCH 260 — Audio calling: core schema
--
--  Adventist Super App gets voice calls — 1:1 and small group, audio
--  only. This patch is the DATA half. The RPCs that enforce who may
--  call whom are patch_261; the Realtime signalling authorisation is
--  patch_262; the sweeper that kills stale calls is patch_263.
--
--  ## What lives where, and why
--
--  Three planes, deliberately kept apart:
--
--    * **Authority — Postgres.** Who is in a call, what state it is in,
--      when it connected, how long it ran. Every transition goes
--      through a SECURITY DEFINER RPC so the client cannot assert it.
--    * **Signalling — Supabase Realtime broadcast.** SDP offers and
--      answers, ICE candidates, mute flags. High-frequency, worthless
--      five seconds later, and NOT written to any table. patch_262
--      gates the channel with RLS.
--    * **Media — WebRTC.** Never touches Supabase at all. No audio is
--      recorded, stored, proxied or transcribed, here or anywhere else.
--
--  The reason for the split is cost as much as design. ICE negotiation
--  for a five-way mesh is a few hundred messages; as table rows that is
--  a few hundred writes, a few hundred WAL records and a few hundred
--  realtime fan-outs per call, for data nobody ever reads again.
--
--  ## room_token is a capability, not a name
--
--  `calls.room_token` is a random UUID and it is the Realtime topic:
--  `call:<room_token>`. It is handed out ONLY by `call_join`
--  (patch_261) and only to a participant the server has already
--  authorised.
--
--  This matters because this project still allows PUBLIC realtime
--  channels — presence (`online_users`), typing and the quiz arena all
--  use them, so "disable public channels" is not available as a
--  hardening step. A public join is not RLS-checked, so a guessable
--  topic would be readable by anyone signed in. 122 bits of entropy is
--  what closes that, and patch_262's RLS policy is the second lock for
--  clients that join privately (which ours do).
--
--  Never log `room_token`, never put it in a notification body, and
--  never derive it from the call id.
--
--  ## No audio, ever
--
--  There is no column here that could hold a recording, and there is no
--  storage bucket for calls. `call_events.detail` is JSONB for
--  diagnostics — connection type, ICE state, error codes — and the
--  RPCs that write it whitelist the keys. If a future change wants to
--  record calls, that is a product/legal decision with a disclosure
--  requirement, not a schema tweak.
--
--  IDEMPOTENT: yes. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. calls — one row per call, 1:1 or group.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.calls (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- The signalling capability. See the header — this is a secret.
  room_token        UUID NOT NULL DEFAULT gen_random_uuid(),

  kind              TEXT NOT NULL
                      CHECK (kind IN ('direct', 'group')),

  -- Group calls hang off an existing group conversation, so membership,
  -- admin rights and the block rules are the ones the chat already has.
  -- Direct calls carry the 1:1 conversation when there is one, purely so
  -- call history can deep-link into the thread; it may be NULL.
  conversation_id   BIGINT REFERENCES public.conversations(id) ON DELETE SET NULL,

  created_by        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Server-side lifecycle. Deliberately only three values: the client's
  -- state machine has more (connecting, reconnecting, …) but those are
  -- LOCAL — a caller reconnecting has not changed anything the callee's
  -- server row should know about.
  status            TEXT NOT NULL DEFAULT 'ringing'
                      CHECK (status IN ('ringing', 'active', 'ended')),

  -- Why it stopped. Set exactly once, by call_end (patch_261).
  end_reason        TEXT
                      CHECK (end_reason IS NULL OR end_reason IN (
                        'completed',      -- someone hung up a connected call
                        'rejected',       -- callee declined
                        'cancelled',      -- caller gave up before answer
                        'missed',         -- rang out
                        'busy',           -- callee already in a call
                        'unreachable',    -- no device could be rung
                        'failed',         -- media never established
                        'max_duration',   -- hit the per-call ceiling
                        'quota',          -- hit a usage quota
                        'stale',          -- swept by the janitor
                        'admin'           -- ended by a super admin
                      )),

  -- invited → the ring started here.
  started_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- The FIRST moment two participants were simultaneously joined. This
  -- is the only clock that counts: ringing time is free, and a call that
  -- never connects bills zero. Set once, never moved.
  connected_at      TIMESTAMPTZ,
  ended_at          TIMESTAMPTZ,

  -- Billed seconds = ended_at - connected_at, stamped by call_end so the
  -- number cannot drift when rows are read later.
  duration_seconds  INTEGER NOT NULL DEFAULT 0
                      CHECK (duration_seconds >= 0),

  -- Snapshot of the ceiling in force when this call started, so raising
  -- the config later cannot retroactively extend a call already running,
  -- and lowering it cannot retroactively invalidate one.
  max_participants  SMALLINT NOT NULL DEFAULT 2
                      CHECK (max_participants BETWEEN 2 AND 16),
  peak_participants SMALLINT NOT NULL DEFAULT 0,

  -- Hard clocks the sweeper reads. Both are absolute, both are stamped
  -- at creation from app_config, both are what makes an abandoned call
  -- self-healing rather than a row that says "active" forever.
  ring_expires_at   TIMESTAMPTZ NOT NULL,
  hard_expires_at   TIMESTAMPTZ NOT NULL,

  -- Bumped by call_heartbeat. A call whose participants have all gone
  -- silent for longer than the grace window is dead, whatever it says.
  last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The token is the channel name; a collision would cross two calls' wires.
CREATE UNIQUE INDEX IF NOT EXISTS calls_room_token_key
  ON public.calls (room_token);

-- The sweeper's working set: everything not yet ended, oldest first.
CREATE INDEX IF NOT EXISTS calls_live_idx
  ON public.calls (status, ring_expires_at)
  WHERE status <> 'ended';

CREATE INDEX IF NOT EXISTS calls_created_by_idx
  ON public.calls (created_by, started_at DESC);

CREATE INDEX IF NOT EXISTS calls_conversation_idx
  ON public.calls (conversation_id, started_at DESC)
  WHERE conversation_id IS NOT NULL;


-- ---------------------------------------------------------------------
--  2. call_participants — who was asked, who turned up, for how long.
--
--  This is also the busy/concurrency ledger: "is this member already on
--  a call" is a lookup here, not a guess from the client.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.call_participants (
  call_id           UUID NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  role              TEXT NOT NULL DEFAULT 'callee'
                      CHECK (role IN ('caller', 'callee')),

  -- Per-person outcome. The call's own end_reason is about the call;
  -- this is about one member's part in it, which in a group call can
  -- differ for every row.
  status            TEXT NOT NULL DEFAULT 'invited'
                      CHECK (status IN (
                        'invited',   -- row created, device not yet rung
                        'ringing',   -- device has the invite and is alerting
                        'joined',    -- accepted and in the room
                        'left',      -- hung up / walked out of a group call
                        'rejected',  -- declined
                        'missed',    -- never answered before the ring expired
                        'busy',      -- was already on another call
                        'failed',    -- accepted but media never came up
                        'removed'    -- ejected by the host
                      )),

  invited_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  ringing_at        TIMESTAMPTZ,
  joined_at         TIMESTAMPTZ,
  left_at           TIMESTAMPTZ,

  duration_seconds  INTEGER NOT NULL DEFAULT 0
                      CHECK (duration_seconds >= 0),

  muted             BOOLEAN NOT NULL DEFAULT FALSE,

  -- Self-reported by the device, used ONLY for cost analysis: a call
  -- where both ends report `relayed` cost TURN bandwidth, one where
  -- neither does cost nothing. Untrusted by design — nothing is
  -- authorised on it.
  network           TEXT
                      CHECK (network IS NULL OR network IN ('wifi', 'mobile', 'other')),
  relayed           BOOLEAN,

  last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (call_id, user_id)
);

-- "Am I / is she already on a call?" — the busy check, and the
-- concurrency ceiling. Partial so it stays tiny: live rows only.
CREATE INDEX IF NOT EXISTS call_participants_live_idx
  ON public.call_participants (user_id, status)
  WHERE status IN ('invited', 'ringing', 'joined');

-- Call history for one member, newest first.
CREATE INDEX IF NOT EXISTS call_participants_user_idx
  ON public.call_participants (user_id, invited_at DESC);


-- ---------------------------------------------------------------------
--  3. call_events — the audit/diagnostic trail.
--
--  Observability (§52) without recording anything private. Rows are
--  written by the RPCs, never by clients, and pruned nightly.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.call_events (
  id          BIGSERIAL PRIMARY KEY,
  call_id     UUID REFERENCES public.calls(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  event       TEXT NOT NULL,
  -- Whitelisted diagnostic keys only (see call_log_event in patch_261).
  detail      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS call_events_call_idx
  ON public.call_events (call_id, created_at);

CREATE INDEX IF NOT EXISTS call_events_recent_idx
  ON public.call_events (created_at DESC);

-- §37: a call ends ONCE. The end path is idempotent in code as well
-- (call_end takes the row lock and checks status), but a unique index is
-- what makes a second 'ended' row impossible even under a race that gets
-- past the lock. Same for the per-call terminal sweep.
CREATE UNIQUE INDEX IF NOT EXISTS call_events_one_ended
  ON public.call_events (call_id)
  WHERE event = 'ended';


-- ---------------------------------------------------------------------
--  4. call_usage_daily — the quota + cost ledger.
--
--  One row per member per UTC day. Written only by call_end. Kept
--  separate from call_participants because a quota check must be one
--  indexed lookup, not an aggregate over a member's whole call history —
--  that aggregate gets slower every day the app is alive.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.call_usage_daily (
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day             DATE NOT NULL,
  seconds         INTEGER NOT NULL DEFAULT 0 CHECK (seconds >= 0),
  group_seconds   INTEGER NOT NULL DEFAULT 0 CHECK (group_seconds >= 0),
  calls_started   INTEGER NOT NULL DEFAULT 0 CHECK (calls_started >= 0),
  calls_answered  INTEGER NOT NULL DEFAULT 0 CHECK (calls_answered >= 0),
  -- Legs where the device reported TURN relay. The closest thing to a
  -- bandwidth bill this app can measure without instrumenting coturn.
  relayed_seconds INTEGER NOT NULL DEFAULT 0 CHECK (relayed_seconds >= 0),
  PRIMARY KEY (user_id, day)
);

CREATE INDEX IF NOT EXISTS call_usage_daily_day_idx
  ON public.call_usage_daily (day DESC);


-- ---------------------------------------------------------------------
--  5. user_call_devices — where to ring.
--
--  NOT a column on `profiles`, on purpose. `profiles` reads entirely
--  through per-column grants with no table-level SELECT (see the
--  CLAUDE.md checklist and patch_192), and `fcm_token` is deliberately
--  unreadable there. A second push token on that table is one forgotten
--  GRANT away from either leaking or silently never working.
--
--  iOS needs a SEPARATE token from FCM: an incoming call must arrive as
--  an APNs **VoIP** push (PushKit) so CallKit can be reported before the
--  app is even awake. FCM cannot send VoIP pushes, so the push function
--  talks to APNs directly and needs this token.
--
--  Nobody can SELECT this table — not even its owner. It is written
--  through call_register_device() (patch_261) and read only by the
--  service role inside the push Edge Function.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_call_devices (
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  platform    TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  -- APNs VoIP token (iOS). Hex string from PushKit.
  voip_token  TEXT,
  -- FCM registration token (Android). Mirrors profiles.fcm_token but is
  -- refreshed by the call stack so a call push never depends on whether
  -- the chat push pipeline happened to run first.
  push_token  TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, platform)
);


-- ---------------------------------------------------------------------
--  6. RLS
--
--  Reads are scoped to "calls I was part of" (§17: nobody sees anyone
--  else's call history). Writes are RPC-only everywhere — there is no
--  INSERT/UPDATE/DELETE policy on any of these tables for a client
--  role, so a client cannot fabricate a call, forge an acceptance,
--  or edit a duration.
-- ---------------------------------------------------------------------
ALTER TABLE public.calls              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_participants  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_usage_daily   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_call_devices  ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER so the participant lookup cannot recurse back through
-- call_participants' own policy. Same shape as is_conversation_member.
CREATE OR REPLACE FUNCTION public.is_call_participant(p_call UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.call_participants p
     WHERE p.call_id = p_call
       AND p.user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_call_participant(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_call_participant(UUID) TO authenticated;

DROP POLICY IF EXISTS calls_select_participant ON public.calls;
CREATE POLICY calls_select_participant ON public.calls
  FOR SELECT TO authenticated
  USING (public.is_call_participant(id));

DROP POLICY IF EXISTS call_participants_select_participant ON public.call_participants;
CREATE POLICY call_participants_select_participant ON public.call_participants
  FOR SELECT TO authenticated
  USING (public.is_call_participant(call_id));

-- Diagnostics are for the server and the admin console, not for members.
-- No SELECT policy at all: RLS with zero permissive policies denies
-- everything, which is what we want for authenticated/anon. The admin
-- console reads through a SECURITY DEFINER RPC (patch_264).
DROP POLICY IF EXISTS call_events_no_client_access ON public.call_events;
CREATE POLICY call_events_no_client_access ON public.call_events
  FOR ALL USING (FALSE) WITH CHECK (FALSE);

-- A member may read their OWN usage — the calls screen shows "X of Y
-- minutes used today" and that number has to come from somewhere.
DROP POLICY IF EXISTS call_usage_select_self ON public.call_usage_daily;
CREATE POLICY call_usage_select_self ON public.call_usage_daily
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Push tokens: nobody. Written through an RPC, read by service role.
DROP POLICY IF EXISTS user_call_devices_no_client_access ON public.user_call_devices;
CREATE POLICY user_call_devices_no_client_access ON public.user_call_devices
  FOR ALL USING (FALSE) WITH CHECK (FALSE);

-- Table grants. SELECT only, and only where a policy above allows it —
-- belt and braces, so a future permissive policy added by mistake still
-- cannot turn into an INSERT path.
GRANT SELECT ON public.calls             TO authenticated;
GRANT SELECT ON public.call_participants TO authenticated;
GRANT SELECT ON public.call_usage_daily  TO authenticated;
REVOKE ALL ON public.call_events       FROM authenticated, anon;
REVOKE ALL ON public.user_call_devices FROM authenticated, anon;


-- ---------------------------------------------------------------------
--  7. Configuration (§53)
--
--  Every tunable in one place, in the app_config key/value table that
--  patch_091 already created and patch_224 already made read-only for
--  clients. Nothing below is hard-coded in Dart except as a fallback
--  for the very first launch before the config has been fetched.
--
--  ## How these numbers were chosen
--
--  They are ABUSE + COST ceilings, not a product tier — the same
--  posture patch_191 set for message/post limits, and for the same
--  reason: a limit the app has a commercial reason to want to bite is
--  a limit that will be tuned for the wrong purpose. At ~215 members
--  the problem is that nobody is calling yet, not that too many are.
--
--    ring_timeout_seconds     45   WhatsApp rings for ~45s. Longer and
--                                  the caller has already given up;
--                                  shorter and a phone in a bag never
--                                  gets picked up.
--    max_group_participants    5   The ceiling the MESH media
--                                  architecture actually supports. Each
--                                  member sends one Opus stream to
--                                  every other, so at 5 the worst leg
--                                  is 4 x ~32 kbps ≈ 128 kbps up. At 8
--                                  it is 224 kbps and a mid-range
--                                  Android is running 7 encoders. Raise
--                                  this ONLY together with an SFU —
--                                  see docs/CALLING_SETUP.md.
--    max_direct_call_minutes 120   A two-hour 1:1 is a real thing
--                                  people do. Past that it is almost
--                                  always a phone left in a pocket,
--                                  which is pure TURN cost.
--    max_group_call_minutes   90
--    free_daily_minutes      120   Cost brake, not a paywall. Nobody on
--    free_monthly_minutes   1500   this network is near either number.
--    premium_daily_minutes   360
--    premium_monthly_minutes 4500
--    max_concurrent_calls      1   Call waiting is NOT implemented
--                                  (§19 says start simple and reliable),
--                                  so a second inbound call is answered
--                                  by the server with 'busy'.
--
--  Changing any of these is an UPDATE to app_config and takes effect on
--  the next call — no deploy, no app update.
-- ---------------------------------------------------------------------
INSERT INTO public.app_config (key, value) VALUES
  ('call.enabled',                    'true'),
  ('call.ring_timeout_seconds',       '45'),
  ('call.connect_timeout_seconds',    '45'),
  ('call.max_group_participants',     '5'),
  ('call.max_direct_call_minutes',    '120'),
  ('call.max_group_call_minutes',     '90'),
  ('call.free_daily_minutes',         '120'),
  ('call.free_monthly_minutes',       '1500'),
  ('call.premium_daily_minutes',      '360'),
  ('call.premium_monthly_minutes',    '4500'),
  ('call.max_concurrent_calls',       '1'),
  -- Rate limits (§28/§29/§30). window seconds : max.
  ('call.rate_attempts_max',          '10'),
  ('call.rate_attempts_window',       '600'),
  ('call.rate_per_recipient_max',     '3'),
  ('call.rate_per_recipient_window',  '600'),
  ('call.rate_unanswered_max',        '20'),
  ('call.rate_unanswered_window',     '3600'),
  ('call.rate_group_create_max',      '6'),
  ('call.rate_group_create_window',   '3600'),
  ('call.rate_group_invite_max',      '30'),
  ('call.rate_group_invite_window',   '3600'),
  ('call.rate_join_max',              '10'),
  ('call.rate_join_window',           '60'),
  ('call.rate_signal_max',            '600'),
  ('call.rate_signal_window',         '60'),
  ('call.rate_ice_max',               '30'),
  ('call.rate_ice_window',            '600'),
  -- Stale-call janitor.
  ('call.heartbeat_seconds',          '15'),
  ('call.stale_grace_seconds',        '75'),
  -- Whether a stranger may ring you at all, or must first be a friend /
  -- someone you have already replied to in chat. TRUE mirrors the
  -- non-friend message cap: a stranger gets three messages, never a
  -- ringing phone.
  ('call.require_friend_or_reply',    'true'),
  -- TURN credential lifetime handed out by the call-ice-servers Edge
  -- Function. Short enough that a leaked credential is worthless before
  -- it can be shared, long enough to survive a slow negotiation.
  ('call.turn_credential_ttl_seconds','600')
ON CONFLICT (key) DO NOTHING;


-- ---------------------------------------------------------------------
--  8. Config readers
--
--  STABLE + SECURITY DEFINER so RPCs can read the config regardless of
--  what app_config's own RLS says today or tomorrow. Every reader takes
--  a fallback, so a missing key degrades to a sane number rather than
--  a NULL that silently disables a limit.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_cfg_int(p_key TEXT, p_default INTEGER)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT NULLIF(regexp_replace(value, '[^0-9-]', '', 'g'), '')::INTEGER
       FROM public.app_config WHERE key = p_key),
    p_default);
$$;

CREATE OR REPLACE FUNCTION public.call_cfg_bool(p_key TEXT, p_default BOOLEAN)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT lower(trim(value)) IN ('true', 't', '1', 'yes', 'on')
       FROM public.app_config WHERE key = p_key),
    p_default);
$$;

REVOKE ALL ON FUNCTION public.call_cfg_int(TEXT, INTEGER)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.call_cfg_bool(TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- The subset the CLIENT is allowed to know, in one round trip. Limits
-- the app needs so it can show "you have used 40 of 120 minutes today"
-- and stop a call before it dials rather than after. Deliberately does
-- NOT expose the rate-limit values — telling a spammer the exact ceiling
-- is telling them exactly how to sit under it.
CREATE OR REPLACE FUNCTION public.call_client_config()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'enabled',                 public.call_cfg_bool('call.enabled', TRUE),
    'ring_timeout_seconds',    public.call_cfg_int('call.ring_timeout_seconds', 45),
    'connect_timeout_seconds', public.call_cfg_int('call.connect_timeout_seconds', 45),
    'max_group_participants',  public.call_cfg_int('call.max_group_participants', 5),
    'max_direct_minutes',      public.call_cfg_int('call.max_direct_call_minutes', 120),
    'max_group_minutes',       public.call_cfg_int('call.max_group_call_minutes', 90),
    'heartbeat_seconds',       public.call_cfg_int('call.heartbeat_seconds', 15)
  );
$$;

REVOKE ALL ON FUNCTION public.call_client_config() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.call_client_config() TO authenticated;


-- ---------------------------------------------------------------------
--  9. Retention
--
--  Fold call diagnostics into the nightly prune patch_190/191 already
--  runs, so no new cron job and no table that grows forever.
--
--  call_events is diagnostics — 30 days is well past the point anyone
--  would investigate a dropped call. `calls` and `call_participants`
--  are HISTORY and are NOT pruned here; they are what the member's own
--  Calls tab reads.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, cron
AS $$
DECLARE
  v_resp_bytes BIGINT;
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';

  SELECT pg_total_relation_size('net._http_response') INTO v_resp_bytes;
  IF v_resp_bytes > 20 * 1024 * 1024 THEN
    EXECUTE 'VACUUM FULL net._http_response';
  END IF;

  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';

  -- patch_191.
  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';

  -- patch_260: call diagnostics. History (calls / call_participants) is
  -- deliberately untouched.
  DELETE FROM public.call_events WHERE created_at < now() - interval '30 days';
END;
$$;

REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_operational_logs() FROM authenticated, anon;


-- =====================================================================
--  VERIFY (run these after applying; read the output)
--
--    SELECT table_name FROM information_schema.tables
--     WHERE table_schema='public'
--       AND table_name IN ('calls','call_participants','call_events',
--                          'call_usage_daily','user_call_devices')
--     ORDER BY 1;
--    -- expect 5 rows
--
--    SELECT key, value FROM public.app_config
--     WHERE key LIKE 'call.%' ORDER BY key;
--    -- expect 30 rows
--
--    SELECT relname, relrowsecurity FROM pg_class
--     WHERE relname IN ('calls','call_participants','call_events',
--                       'call_usage_daily','user_call_devices');
--    -- relrowsecurity must be TRUE for all five
--
--    SELECT public.call_client_config();
--    -- expect the JSON object, ring_timeout_seconds = 45
-- =====================================================================
