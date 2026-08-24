-- =====================================================================
--  PATCH 238 — Advent AI, part 3: configuration + service state
--
--  Every limit, price and switch in Advent AI lives here as an
--  app_config row, so all of it is changeable from the Supabase
--  dashboard without shipping an APK. Nothing in the Flutter app or the
--  edge function hard-codes a limit; they read these and fall back to a
--  safe default if a key is missing (a typo must never take the feature
--  down — see ai_config_int in patch_237).
--
--  ## THREE ways Advent AI can be unavailable, and they are not the same
--
--  Conflating these is how a member gets blamed for the founder's card
--  expiring, so the vocabulary is fixed here and the app maps each code
--  to its own screen:
--
--   1. `out_of_credit`  — THIS MEMBER has no messages left.
--        Their problem, and they can fix it. Offer funding.
--
--   2. `free_pool_closed` — the app-wide FREE allocation is exhausted
--        (lifetime or today). This member never had messages to use up,
--        so telling them "you've used yours" would be a lie. Offer
--        funding; paying members are completely unaffected.
--
--   3. `service_suspended` — the PROVIDER is refusing us: billing lapsed,
--        card declined, quota exceeded, account suspended. This hits
--        EVERYONE, including members who have paid. Nobody is charged,
--        and — this is the important part — the funding button is
--        HIDDEN. Selling more credit for a service that is currently
--        dead is precisely the dark pattern the brief forbids.
--
--  State 3 trips AUTOMATICALLY. The edge function calls
--  ai_trip_service_suspended() when the provider returns a billing or
--  quota rejection, which stops the app hammering a dead endpoint and
--  notifies every super admin so the founder hears it from the app
--  rather than from a member.
--
--  IDEMPOTENT: yes — every key is an upsert.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Config keys
--
--  app_config is (key, value, updated_at) with value as TEXT. Numbers
--  are read through ai_config_int(); strings are read directly.
-- ---------------------------------------------------------------------
INSERT INTO public.app_config (key, value) VALUES
  -- ---- provider -----------------------------------------------------
  -- Swapping provider or model is a one-row edit. The edge function's
  -- AiProvider abstraction resolves both at request time.
  ('ai_provider',                 'gemini'),
  ('ai_model',                    'gemini-2.5-flash-lite'),

  -- ---- service state ------------------------------------------------
  --   live      — normal
  --   suspended — provider refusing us (billing/quota). Auto-set.
  --   off       — deliberately switched off by the founder.
  ('ai_service_state',            'live'),
  ('ai_service_state_note',       ''),

  -- ---- what a member gets -------------------------------------------
  -- The free SAMPLE. Ten, not twenty (founder, 23 Aug 2026) — and the
  -- reasoning is worth keeping, because the obvious instinct is to cut
  -- it further and that instinct is wrong:
  --
  --   * Exposure per member is tiny either way. At the worst-case cost
  --     of one message (~$0.0013) ten messages is $0.013, so the $10
  --     lifetime pool covers ~770 members' full sample even if every one
  --     of them writes maximum-length questions.
  --   * The thing that actually protects the card is
  --     ai_global_free_pool_micros below, NOT this number. Free usage
  --     stops dead when the pool is spent, however many accounts exist.
  --   * Cutting to 5 is a false economy: a member asks one question and
  --     two follow-ups, hits the wall before they have felt why it is
  --     worth paying for, and the money is spent with no subscriber to
  --     show for it. Ten leaves room for a real exchange plus an
  --     app-help question.
  ('ai_free_grant_units',         '10'),

  -- ---- what Premium includes ----------------------------------------
  -- 500/month is ~16 a day: past any genuine use, while capping the
  -- worst case at $0.65/month against ~$2.10-2.55 net subscription
  -- income. Unused messages do NOT roll over (see ai_sync_allowance).
  ('ai_premium_monthly_units',    '500'),

  -- ---- per-member rate limits ---------------------------------------
  -- Premium members get the higher pair. These stop runaway loops and
  -- scripted abuse; they are NOT meant to be reachable by a real person
  -- having a real conversation.
  ('ai_rate_free_per_min',        '5'),
  ('ai_rate_free_per_day',        '10'),
  ('ai_rate_premium_per_min',     '10'),
  ('ai_rate_premium_per_day',     '200'),

  -- ---- the ceilings protecting the founder's card -------------------
  -- Micro-dollars of REAL provider spend. FREE usage only — a Premium
  -- member has already paid and is never measured against these.
  --
  --   10000000 micros = $10.00 lifetime  (the whole card)
  --     250000 micros =  $0.25 per UTC day
  --
  -- The daily cap is the dial that manages risk, not the sample size:
  -- at $0.25/day the lifetime pool cannot be drained in under 40 days,
  -- so a spike, a bug or a scripted attack is something the founder has
  -- weeks to notice rather than hours.
  ('ai_global_free_pool_micros',  '10000000'),
  ('ai_global_daily_cap_micros',  '250000'),

  -- ---- request shape ------------------------------------------------
  -- These bound the WORST-CASE cost of a single message, which is what
  -- makes flat per-message billing safe (see patch_237's header).
  ('ai_max_request_chars',        '2000'),
  ('ai_max_context_tokens',       '8000'),
  ('ai_max_output_tokens',        '1200'),
  ('ai_max_context_messages',     '12'),
  ('ai_max_tool_calls',           '4'),

  -- ---- provider pricing, micro-dollars per 1M tokens ----------------
  -- gemini-2.5-flash-lite paid tier: $0.10 in / $0.40 out per 1M.
  -- Used ONLY to compute real spend for the ceilings above. Members are
  -- billed in flat message units and never see these.
  -- UPDATE THESE if the model or the provider's prices change, or the
  -- ceilings will be measuring the wrong thing.
  ('ai_price_in_micros_per_mtok',  '100000'),
  ('ai_price_out_micros_per_mtok', '400000'),

  -- ---- entitlement --------------------------------------------------
  -- There are NO consumable top-up products. Advent AI is included with
  -- the existing $3/month Premium subscription, so entitlement flows
  -- through `profiles.premium_until` — written only by
  -- supabase/functions/verify-purchase after Google Play confirms the
  -- subscription. This feature adds no second billing path, and no new
  -- Play product needs to exist for it to ship.
  ('ai_entitlement',              'premium')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- ---------------------------------------------------------------------
--  Service status, as the client sees it.
--
--  One call the app can make to know whether to show the composer at
--  all. Combines the founder's switch with the live free-pool state, so
--  the app never has to work any of it out for itself.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_service_status()
RETURNS TABLE (
  state          TEXT,
  available      BOOLEAN,
  free_pool_open BOOLEAN,
  -- False when funding must not be offered: the service is down, so
  -- taking money for it would be indefensible.
  can_fund       BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_state TEXT;
BEGIN
  SELECT COALESCE(value, 'live') INTO v_state
    FROM public.app_config WHERE key = 'ai_service_state';
  v_state := COALESCE(v_state, 'live');

  RETURN QUERY SELECT
    v_state,
    (v_state = 'live'),
    (v_state = 'live' AND public.ai_free_pool_open()),
    (v_state = 'live');
END;
$$;

GRANT EXECUTE ON FUNCTION public.ai_service_status() TO authenticated;

-- ---------------------------------------------------------------------
--  Trip the breaker.
--
--  Called by the edge function when the provider rejects us for billing
--  or quota reasons. Three jobs:
--    1. stop every further request (no point, and each one costs a
--       round trip and a member's patience);
--    2. record WHY, so the founder is not debugging blind;
--    3. tell the founder, once, through the notification the app
--       already fans out to push.
--
--  Deliberately NOT granted to clients. service_role only.
--
--  Idempotent: re-tripping an already-suspended service updates the note
--  but does not send a second notification, so a burst of failures is
--  one alert rather than fifty.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_trip_service_suspended(p_reason TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_was TEXT;
  v_admin RECORD;
BEGIN
  SELECT COALESCE(value, 'live') INTO v_was
    FROM public.app_config WHERE key = 'ai_service_state';

  INSERT INTO public.app_config (key, value)
  VALUES ('ai_service_state', 'suspended')
  ON CONFLICT (key) DO UPDATE SET value = 'suspended', updated_at = NOW();

  INSERT INTO public.app_config (key, value)
  VALUES ('ai_service_state_note', LEFT(COALESCE(p_reason, ''), 500))
  ON CONFLICT (key) DO UPDATE
    SET value = LEFT(COALESCE(p_reason, ''), 500), updated_at = NOW();

  -- Only alert on the TRANSITION into suspension.
  IF COALESCE(v_was, 'live') <> 'suspended' THEN
    FOR v_admin IN
      SELECT id FROM public.profiles WHERE is_super_admin = TRUE
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_type)
      VALUES (
        v_admin.id,
        'Advent AI has paused',
        'Advent AI stopped because the AI provider refused our requests — '
          || 'usually billing or quota. Members are seeing a "temporarily '
          || 'unavailable" message and nobody is being charged. Check the '
          || 'provider billing account, then set ai_service_state back to '
          || '"live".',
        'ai_service',
        'ai_service'
      );
    END LOOP;
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.ai_trip_service_suspended(TEXT)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
--  Bring it back. Founder-facing convenience so recovery is one call
--  rather than remembering two key names.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_resume_service()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'ai_resume_service: super admin only';
  END IF;

  INSERT INTO public.app_config (key, value) VALUES ('ai_service_state', 'live')
  ON CONFLICT (key) DO UPDATE SET value = 'live', updated_at = NOW();

  INSERT INTO public.app_config (key, value) VALUES ('ai_service_state_note', '')
  ON CONFLICT (key) DO UPDATE SET value = '', updated_at = NOW();

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ai_resume_service() TO authenticated;
-- (the is_super_admin() guard inside is the real gate; the grant only
--  makes it callable from the admin dashboard at all)

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- SELECT key, value FROM public.app_config WHERE key LIKE 'ai_%' ORDER BY key;
--
-- SELECT * FROM public.ai_service_status();
--   -- expect: live | t | t | t
--
-- -- Simulate the card dying, then check the app's answer:
-- --   SELECT public.ai_trip_service_suspended('billing test');
-- --   SELECT * FROM public.ai_service_status();
-- --     -- expect: suspended | f | f | f   (can_fund FALSE is the point)
-- --   SELECT public.ai_resume_service();
-- =====================================================================
