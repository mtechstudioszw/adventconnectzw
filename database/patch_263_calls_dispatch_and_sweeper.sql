-- =====================================================================
--  PATCH 263 — Call push dispatch + the stale-call janitor
--
--  Two jobs that both exist because a phone is not a reliable narrator.
--
--  ## 1. Dispatch (§11, §41)
--
--  A Supabase Realtime subscription cannot wake a killed app. Nothing
--  can, on either platform, except a push — and on iOS specifically
--  only an APNs **VoIP** push, which FCM cannot send at all. So when a
--  participant row is created in 'invited', a trigger fires pg_net at
--  the `call-push` Edge Function, which looks up that member's devices
--  and sends the right kind of push to each.
--
--  This is deliberately NOT routed through the `notifications` table
--  and the existing notify-fcm webhook. Three reasons:
--
--    * A ringing phone is not an inbox item. Writing a notifications
--      row would leave a permanent "incoming call" entry that outlives
--      the 45-second ring.
--    * notify-fcm sends a normal-priority display notification. An
--      incoming call needs a data-only, high-priority push that the
--      device turns into a full-screen CallKit / CallStyle UI.
--    * iOS needs APNs directly, which notify-fcm has no path to.
--
--  The missed-call notification, which IS an inbox item, still goes
--  through `notifications` — call_finalize (patch_261) writes it.
--
--  ## 2. Cancellation dispatch (§22, "no ghost calls")
--
--  When a call ends while someone's phone is still ringing, that phone
--  must be told, or the callee is left staring at a CallKit screen for
--  a call that no longer exists — and on iOS, a CallKit call that is
--  never reported as ended will eventually get the app killed by the
--  system. So ending a call fires a second dispatch that tells every
--  still-ringing device to dismiss.
--
--  ## 3. The janitor (§50, §51)
--
--  Every clock a call depends on is server-side and absolute, so an app
--  that force-quits, crashes, or drives into a tunnel cannot leave a
--  row saying "active" forever. Runs every minute, and each pass is
--  cheap: the working set is the partial index `calls_live_idx`, which
--  only contains calls that have not ended.
--
--  ## Secrets
--
--  The shared secret that proves a call to `call-push` came from this
--  database lives in Supabase **Vault**, not in app_config (which is
--  world-readable — it carries the minimum build number, checked before
--  sign-in) and not in this file. Set it once with:
--
--    SELECT vault.create_secret('<random>', 'call_push_secret',
--                               'Auth header for the call-push fn');
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Where to send, and what proves it was us
-- ---------------------------------------------------------------------

-- The Edge Function base. In app_config rather than hard-coded so a
-- project move does not need a patch; it is not a secret (the URL is in
-- every APK already).
INSERT INTO public.app_config (key, value) VALUES
  ('call.push_endpoint',
   'https://eqbyvasteolqyktbqbem.functions.supabase.co/call-push')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.call_push_secret()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, vault
AS $fn$
DECLARE v TEXT;
BEGIN
  SELECT decrypted_secret INTO v
    FROM vault.decrypted_secrets WHERE name = 'call_push_secret' LIMIT 1;
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  -- Vault absent or unreadable. Handled by the caller, which logs it
  -- rather than silently never ringing anyone.
  RETURN NULL;
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_push_secret()
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  2. Dispatch
--
--  pg_net queues the request and returns immediately, so nothing here
--  is on the critical path of the transaction that started the call —
--  a slow Edge Function delays no one's dial tone.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_dispatch(
  p_call   UUID,
  p_user   UUID,
  p_action TEXT              -- 'ring' | 'cancel'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net
AS $fn$
DECLARE
  v_url    TEXT := public.call_cfg_text_safe('call.push_endpoint', '');
  v_secret TEXT := public.call_push_secret();
BEGIN
  IF v_url = '' THEN RETURN; END IF;

  IF v_secret IS NULL OR length(v_secret) = 0 THEN
    -- Loud in the audit trail, silent to the member. Without this the
    -- symptom is "calls never ring on a locked phone" with nothing
    -- anywhere to explain it.
    PERFORM public.call_log_event(p_call, p_user, 'push_unconfigured',
      jsonb_build_object('reason', 'no vault secret call_push_secret'));
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'x-call-secret', v_secret),
    body    := jsonb_build_object(
                 'call_id', p_call,
                 'user_id', p_user,
                 'action',  p_action),
    timeout_milliseconds := 5000
  );
EXCEPTION WHEN OTHERS THEN
  -- A push that cannot be dispatched must never roll back the call it
  -- belongs to. The in-app path (Realtime) still rings a foregrounded
  -- device, so a failure here degrades rather than breaks.
  PERFORM public.call_log_event(p_call, p_user, 'push_failed',
    jsonb_build_object('code', SQLSTATE));
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_dispatch(UUID, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;


-- patch_260 shipped call_cfg_int and call_cfg_bool but no text reader,
-- and the endpoint above needs one. Named `_safe` so it cannot collide
-- with a differently-shaped call_cfg_text added later.
CREATE OR REPLACE FUNCTION public.call_cfg_text_safe(p_key TEXT, p_default TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $fn$
  SELECT COALESCE(
    (SELECT NULLIF(trim(value), '') FROM public.app_config WHERE key = p_key),
    p_default);
$fn$;

REVOKE ALL ON FUNCTION public.call_cfg_text_safe(TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;


-- ---- ring ------------------------------------------------------------
--
-- Fires when a callee row appears. The `auth.uid() IS DISTINCT FROM
-- NEW.user_id` guard is load-bearing: call_join (patch_261) inserts the
-- joiner's OWN row as 'invited' before immediately accepting it, and
-- without this that member would push themselves an incoming call for a
-- call they are already walking into.
CREATE OR REPLACE FUNCTION public.call_on_participant_invited()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NEW.status = 'invited'
     AND NEW.role = 'callee'
     AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM NEW.user_id) THEN
    PERFORM public.call_dispatch(NEW.call_id, NEW.user_id, 'ring');
  END IF;
  RETURN NULL;   -- AFTER trigger; return value is ignored.
END;
$fn$;

DROP TRIGGER IF EXISTS trg_call_participant_invited ON public.call_participants;
CREATE TRIGGER trg_call_participant_invited
  AFTER INSERT ON public.call_participants
  FOR EACH ROW EXECUTE FUNCTION public.call_on_participant_invited();


-- ---- cancel ----------------------------------------------------------
--
-- One dispatch per device that is still being alerted, at the moment
-- the call goes to 'ended'. Anyone already joined has a live Realtime
-- channel and learns from that, so they are skipped — this is only for
-- phones whose app may not even be running.
CREATE OR REPLACE FUNCTION public.call_on_ended()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE r RECORD;
BEGIN
  IF NEW.status <> 'ended' OR OLD.status = 'ended' THEN RETURN NULL; END IF;

  FOR r IN
    SELECT user_id FROM public.call_participants
     WHERE call_id = NEW.id
       AND status IN ('missed', 'rejected', 'busy', 'invited', 'ringing')
  LOOP
    PERFORM public.call_dispatch(NEW.id, r.user_id, 'cancel');
  END LOOP;
  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_call_ended_dispatch ON public.calls;
CREATE TRIGGER trg_call_ended_dispatch
  AFTER UPDATE OF status ON public.calls
  FOR EACH ROW EXECUTE FUNCTION public.call_on_ended();

REVOKE ALL ON FUNCTION public.call_on_participant_invited()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.call_on_ended()
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  3. Per-participant sweep
--
--  A group call where ONE phone dies must lose that one participant,
--  not the whole room. Mirrors call_leave's accounting exactly — the
--  seconds are still billed, because they were still spent.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_sweep_participant(
  p_call UUID, p_user UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_p    public.call_participants%ROWTYPE;
  v_kind TEXT;
  v_secs INTEGER := 0;
BEGIN
  SELECT * INTO v_p FROM public.call_participants
   WHERE call_id = p_call AND user_id = p_user FOR UPDATE;
  IF NOT FOUND OR v_p.status <> 'joined' THEN RETURN; END IF;

  SELECT kind INTO v_kind FROM public.calls WHERE id = p_call;

  IF v_p.joined_at IS NOT NULL THEN
    v_secs := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_p.joined_at))::INTEGER);
  END IF;

  UPDATE public.call_participants
     SET status = 'left', left_at = now(), duration_seconds = v_secs
   WHERE call_id = p_call AND user_id = p_user;

  IF v_secs > 0 THEN
    INSERT INTO public.call_usage_daily AS u
      (user_id, day, seconds, group_seconds, calls_answered, relayed_seconds)
    VALUES (p_user, (now() AT TIME ZONE 'UTC')::date, v_secs,
            CASE WHEN v_kind = 'group' THEN v_secs ELSE 0 END, 1,
            CASE WHEN v_p.relayed THEN v_secs ELSE 0 END)
    ON CONFLICT (user_id, day) DO UPDATE
      SET seconds         = u.seconds         + EXCLUDED.seconds,
          group_seconds   = u.group_seconds   + EXCLUDED.group_seconds,
          calls_answered  = u.calls_answered  + EXCLUDED.calls_answered,
          relayed_seconds = u.relayed_seconds + EXCLUDED.relayed_seconds;
  END IF;

  PERFORM public.call_log_event(p_call, p_user, 'swept',
    jsonb_build_object('reason', 'heartbeat_lost', 'seconds', v_secs));
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_sweep_participant(UUID, UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  4. The janitor
--
--  Ordered cheapest-first, and every branch routes through
--  call_finalize, which is idempotent — so two overlapping runs (a slow
--  pass still going when the next minute ticks) cannot double-bill
--  anyone or write two 'ended' events.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_sweep_stale()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_grace   INTEGER := public.call_cfg_int('call.stale_grace_seconds', 75);
  v_missed  INTEGER := 0;
  v_maxdur  INTEGER := 0;
  v_stale   INTEGER := 0;
  v_dropped INTEGER := 0;
  r         RECORD;
BEGIN
  -- (a) Rang out. The single most common end state for a call nobody
  --     picked up, and the one that must produce exactly one missed-call
  --     entry — which call_finalize handles.
  FOR r IN
    SELECT id FROM public.calls
     WHERE status = 'ringing' AND ring_expires_at < now()
     LIMIT 500
  LOOP
    PERFORM public.call_finalize(r.id, 'missed');
    v_missed := v_missed + 1;
  END LOOP;

  -- (b) Hit the per-call ceiling. Almost always a phone left in a
  --     pocket, which is pure TURN cost with nobody listening.
  FOR r IN
    SELECT id FROM public.calls
     WHERE status <> 'ended' AND hard_expires_at < now()
     LIMIT 500
  LOOP
    PERFORM public.call_finalize(r.id, 'max_duration');
    v_maxdur := v_maxdur + 1;
  END LOOP;

  -- (c) One participant went quiet in a call that is otherwise alive.
  --     Done BEFORE (d) so a group call sheds the dead leg rather than
  --     being torn down with it.
  FOR r IN
    SELECT p.call_id, p.user_id
      FROM public.call_participants p
      JOIN public.calls c ON c.id = p.call_id
     WHERE c.status <> 'ended'
       AND p.status = 'joined'
       AND p.last_seen_at < now() - make_interval(secs => v_grace)
     LIMIT 500
  LOOP
    PERFORM public.call_sweep_participant(r.call_id, r.user_id);
    v_dropped := v_dropped + 1;
  END LOOP;

  -- (d) Everyone went quiet, or too few are left to have a call at all.
  --     `connected_at IS NOT NULL` picks the honest end reason: a call
  --     that was talking and then lost everyone completed; one that
  --     never connected went stale.
  FOR r IN
    SELECT c.id, c.connected_at,
           (SELECT COUNT(*) FROM public.call_participants p
             WHERE p.call_id = c.id
               AND p.status IN ('joined', 'invited', 'ringing')) AS live
      FROM public.calls c
     WHERE c.status <> 'ended'
       AND c.last_seen_at < now() - make_interval(secs => v_grace)
     LIMIT 500
  LOOP
    PERFORM public.call_finalize(
      r.id,
      CASE WHEN r.connected_at IS NOT NULL THEN 'completed' ELSE 'stale' END);
    v_stale := v_stale + 1;
  END LOOP;

  -- (e) An active call that has dropped below two live participants.
  --     Reached when the last peer leaves without a clean hang-up and
  --     (c) has just removed them.
  FOR r IN
    SELECT c.id, c.connected_at
      FROM public.calls c
     WHERE c.status <> 'ended'
       AND (SELECT COUNT(*) FROM public.call_participants p
             WHERE p.call_id = c.id
               AND p.status IN ('joined', 'invited', 'ringing')) < 2
     LIMIT 500
  LOOP
    PERFORM public.call_finalize(
      r.id,
      CASE WHEN r.connected_at IS NOT NULL THEN 'completed' ELSE 'missed' END);
    v_stale := v_stale + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'missed', v_missed, 'max_duration', v_maxdur,
    'stale', v_stale, 'participants_dropped', v_dropped);
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_sweep_stale()
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  5. Schedule it
--
--  Every minute. The ring timeout is 45s, so worst case a caller sees
--  "ringing" for about 105s before the server calls it missed — but
--  that path is normally driven by the CALLER's own client, which gives
--  up at ring_expires_at and calls call_cancel. The janitor is the
--  backstop for when the caller's app is the thing that died.
-- ---------------------------------------------------------------------
DO $do$
BEGIN
  PERFORM cron.unschedule('call-sweep-stale');
EXCEPTION WHEN OTHERS THEN
  NULL;   -- not scheduled yet; nothing to remove.
END;
$do$;

SELECT cron.schedule(
  'call-sweep-stale',
  '* * * * *',
  $cron$ SELECT public.call_sweep_stale(); $cron$
);


-- =====================================================================
--  VERIFY (run these after applying; read the output)
--
--    SELECT jobname, schedule, active FROM cron.job
--     WHERE jobname = 'call-sweep-stale';
--    -- expect one row, '* * * * *', active = true
--
--    SELECT public.call_sweep_stale();
--    -- expect {"missed":0,"max_duration":0,"stale":0,"participants_dropped":0}
--    -- on a database with no live calls
--
--    SELECT tgname FROM pg_trigger
--     WHERE tgrelid IN ('public.calls'::regclass,
--                       'public.call_participants'::regclass)
--       AND NOT tgisinternal ORDER BY 1;
--    -- expect trg_call_ended_dispatch and trg_call_participant_invited
--
--    -- The push secret MUST be set or no locked phone will ever ring:
--    SELECT public.call_push_secret() IS NOT NULL AS push_configured;
--    -- expect true. If false:
--    --   SELECT vault.create_secret('<random-32-bytes>', 'call_push_secret',
--    --                              'Auth header for the call-push fn');
--    -- and set the SAME value as the CALL_PUSH_SECRET env var on the
--    -- call-push Edge Function.
-- =====================================================================
