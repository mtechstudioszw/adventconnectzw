-- =====================================================================
--  PATCH 268 — Premium TIERS, and the call settings that go with them
--
--  Founder's proposal, 25 Aug 2026: three levels instead of one.
--
--    Plus   US$3  / month  — no ads, 6 hours of calls a day
--    Pro    US$5  / month  — everything in Plus, plus the full Advent
--                            AI allowance
--    Pro    US$30 / year   — the same as Pro monthly, billed yearly.
--                            Carries the promotion badge and is the
--                            default selection on the Premium screen.
--
--  ## ONE product, THREE base plans — and why that is not a shortcut
--
--  A Play product ID can never be changed after creation, and
--  `premium_monthly` is live with an active `monthly` base plan. So the
--  tiers are base plans ON that product:
--
--      premium_monthly
--        ├── monthly      US$3/mo   -> plus
--        ├── pro-monthly  US$5/mo   -> pro
--        └── annual       US$30/yr  -> pro
--
--  Play allows exactly one active base plan per product, which buys
--  mutual exclusivity, native upgrade/downgrade with proration, and one
--  subscription in the member's Play account — all for free. Three
--  separate products would have needed each of those written, and the
--  cost of getting the first one wrong is double-charging somebody.
--
--  It also means `verify-purchase` and `play-rtdn` keep working with ONE
--  new fact: which base plan the purchase used. No second verification
--  path, which is the thing that made a consumable top-up too risky to
--  ship (see lib/services/ai/ai_tiers.dart).
--
--  ## THE profiles CHECKLIST (CLAUDE.md — read it before touching this)
--
--  1. **Privilege trigger: YES.** `premium_tier` is bought, exactly like
--     `premium_until`, so `profiles_block_privilege_self_grant()` snaps
--     it back — and, like premium_until, ABOVE the super-admin bypass,
--     because this is a privilege nobody hands themselves. Without this
--     line a single PATCH /profiles?id=eq.<me> {"premium_tier":"pro"}
--     buys the top tier for nothing. This is the exact trap patch_188
--     was written for.
--  2. **GRANTS: SELECT only.** `authenticated` has NO table-level SELECT
--     on profiles — it reads entirely through per-column grants, so a
--     new column is invisible until granted, and a select that NAMES an
--     ungranted column fails as a whole. PremiumService.refresh() now
--     asks for `premium_until, premium_tier` in one select, so without
--     the grant below premium would stop working for everybody, not
--     merely lose the tier. NO update grant: UPDATE on profiles is
--     per-column since the premium migration, so staying silent here is
--     what keeps it unwritable.
--  3. No table-level SELECT exists, so no REVOKE-ordering trap.
--  4. No BEFORE DELETE trigger touched.
--
--  ## What this patch does NOT do — read before shipping the paywall
--
--  **The Advent AI allowance is not yet split by tier.** Both paid
--  levels still receive `ai_premium_monthly_units` (500). The allowance
--  is decided inside patch_239's `ai_my_balance` / grant functions, in
--  four inlined `ai_config_int('ai_premium_monthly_units', 500)` call
--  sites; changing it means reproducing those functions, which is a
--  separate patch that deserves its own review rather than a rider on
--  this one. `ai_plus_monthly_units` is seeded below so that patch is a
--  one-line change per site.
--
--  The direction of the gap is the safe one: Plus members get MORE than
--  they were promised, never less. But until it lands, Pro's headline
--  ("five times Plus") is not true in the database, so either finish
--  that patch or soften the copy before this sells.
--
--  IDEMPOTENT: yes.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. profiles.premium_tier
-- ---------------------------------------------------------------------

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS premium_tier TEXT;

DO $$
BEGIN
  ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_premium_tier_check
    CHECK (premium_tier IS NULL OR premium_tier IN ('plus', 'pro'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

COMMENT ON COLUMN public.profiles.premium_tier IS
  'Which level of premium. NULL = not subscribed (or a subscription '
  'that predates tiers — see the grandfathering below). Written ONLY by '
  'sync_premium_until() from verified store state, and snapped back by '
  'profiles_block_privilege_self_grant() on any client write. Always '
  'read together with premium_until: this column says WHICH level, that '
  'one says whether it is still in force.';

-- The app must be able to READ its own tier. There is no table-level
-- SELECT to inherit from — see the checklist in the header.
GRANT SELECT (premium_tier) ON public.profiles TO authenticated;

-- Deliberately NO `GRANT UPDATE (premium_tier)`. UPDATE on profiles is
-- per-column, so silence here is the lock.


-- ---------------------------------------------------------------------
--  2. The privilege trigger learns about it
--
--  Re-stated in full rather than patched, because this function is the
--  one place three separate production bugs have come from and reading
--  it whole is the point of the CLAUDE.md rule.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  -- No JWT = the service role (edge functions) or a DB-internal caller.
  -- That is the only path allowed to grant premium.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Premium is BOUGHT, full stop (founder's rule, 3 Aug 2026): nobody
  -- gets an ad-free app for holding a role. Church admins, verified
  -- admins and super admins all see ads and all get the upgrade promo
  -- until they pay like everyone else.
  --
  -- Deliberately applied ABOVE the super-admin bypass below, so it
  -- covers super admins too — this is the one privilege they may not
  -- hand themselves.
  --
  -- BOTH columns. premium_until says whether, premium_tier says which,
  -- and a member who could write the second could give themselves Pro
  -- on a Plus subscription — twelve hours of calls and the full AI
  -- allowance for US$3. (patch_268)
  NEW.premium_until := OLD.premium_until;
  NEW.premium_tier  := OLD.premium_tier;

  SELECT COALESCE(p.is_super_admin, FALSE)
    INTO caller_is_super
    FROM public.profiles p
    WHERE p.id = auth.uid();

  IF caller_is_super THEN
    RETURN NEW;
  END IF;

  NEW.is_super_admin := OLD.is_super_admin;
  NEW.is_verified    := OLD.is_verified;
  NEW.is_banned      := OLD.is_banned;

  -- `is_business` can move TRUE during the auto-approve RPC; otherwise
  -- snap it back to whatever it was before.
  IF current_setting('app.auto_approving_business', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_business := OLD.is_business;
  END IF;

  RETURN NEW;
END;
$function$;


-- ---------------------------------------------------------------------
--  3. subscriptions.base_plan_id — which plan was actually bought
-- ---------------------------------------------------------------------

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS base_plan_id TEXT;

COMMENT ON COLUMN public.subscriptions.base_plan_id IS
  'Play base plan id (monthly / pro-monthly / annual). NULL on rows '
  'written before tiers existed. This is what decides the tier — the '
  'product id is the same string for all three plans and identifies '
  'nothing. Written by verify-purchase and play-rtdn from what the '
  'Play Developer API reports, never from anything the client claims.';


-- ---------------------------------------------------------------------
--  4. base plan -> tier
--
--  MIRRORS BillingConfig.basePlanTiers in the app. This copy is the one
--  that decides; the app's exists so the picker can label a plan before
--  a purchase happens. Change them together.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.premium_tier_for_base_plan(p_plan TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_plan IN ('pro-monthly', 'annual') THEN 'pro'
    -- Everything else, INCLUDING NULL, is the lowest paid tier.
    --
    -- NULL is not a mistake here, it is the grandfather clause: rows
    -- written before this patch have no base plan recorded. Section 6
    -- promotes those particular members to 'pro' explicitly and says
    -- why; this function's job is only to make sure an unrecognised
    -- plan under-grants rather than over-grants, because a support
    -- ticket is cheaper than giving Pro away.
    ELSE 'plus'
  END;
$$;


-- ---------------------------------------------------------------------
--  5. sync_premium_until — now writes the tier as well
--
--  Still the ONLY thing that writes premium. Derives both columns from
--  verified subscription rows in one pass, so they can never disagree:
--  the tier comes from the SAME row that supplied the expiry.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_premium_until(p_user UUID)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_until TIMESTAMPTZ;
  v_tier  TEXT;
BEGIN
  -- Statuses that keep access:
  --   active    — paid and renewing
  --   in_grace  — the store is retrying a failed payment; Google asks
  --               that access continue, and the user usually fixes it
  --   cancelled — auto-renew is off but the current period is paid for
  -- Everything else (on_hold, paused, expired, refunded, revoked,
  -- pending) grants nothing, which is what makes a refund bite at once.
  --
  -- ORDER BY on the same scan, so the tier belongs to the row that set
  -- the date. A member who holds two entitling rows (an old monthly
  -- still inside its paid period plus a new annual, which is exactly
  -- what an upgrade looks like for a few weeks) gets the LONGEST date
  -- and the BEST tier of the rows that reach it — never a Pro date with
  -- a Plus tier.
  SELECT s.current_period_end,
         public.premium_tier_for_base_plan(s.base_plan_id)
    INTO v_until, v_tier
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL
   ORDER BY
     -- 'pro' before 'plus' — alphabetically it already is, but say so.
     CASE public.premium_tier_for_base_plan(s.base_plan_id)
       WHEN 'pro' THEN 0 ELSE 1 END,
     s.current_period_end DESC
   LIMIT 1;

  -- The date is still the MAX across every entitling row: a member must
  -- not lose paid-for days because the best tier expires first.
  SELECT MAX(s.current_period_end)
    INTO v_until
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL;

  UPDATE public.profiles
     SET premium_until = v_until,
         premium_tier  = CASE WHEN v_until IS NULL THEN NULL ELSE v_tier END
   WHERE id = p_user;

  RETURN v_until;
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_premium_until(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_premium_until(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION public.sync_premium_until(UUID) FROM anon;

REVOKE ALL ON FUNCTION public.premium_tier_for_base_plan(TEXT)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  6. Grandfathering — the existing US$3 subscribers
--
--  Everyone who is premium today bought `premium_monthly` when US$3
--  included 500 Advent AI questions on the better model. Splitting the
--  tiers underneath them would take a feature off people who are
--  mid-subscription, which is churn, refund requests, and a bad look in
--  a church app. Google also expects an existing subscription to keep
--  delivering what it was sold as.
--
--  So every subscription that predates tiers — identified by having no
--  base_plan_id recorded — is Pro, for as long as it lasts. When it
--  renews, `play-rtdn` writes the real base plan and they settle onto
--  whatever they are actually paying for.
--
--  Narrow on purpose: only rows that are ENTITLING right now, so this
--  cannot resurrect an expired subscription.
-- ---------------------------------------------------------------------

UPDATE public.profiles p
   SET premium_tier = 'pro'
 WHERE p.premium_until IS NOT NULL
   AND p.premium_until > now()
   AND p.premium_tier IS NULL
   AND EXISTS (
     SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = p.id
        AND s.base_plan_id IS NULL
        AND s.status IN ('active', 'in_grace', 'cancelled')
   );


-- ---------------------------------------------------------------------
--  7. Calls — the tier a member's minutes are metered against
-- ---------------------------------------------------------------------

-- Read defensively, exactly as call_is_premium is and for the same
-- reason: premium is owned by another part of the app, and a change to
-- its schema must never be able to stop calls working. A missing column
-- degrades to the free ceilings rather than raising.
CREATE OR REPLACE FUNCTION public.call_premium_tier(p_user UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $fn$
DECLARE
  v_until TIMESTAMPTZ;
  v_tier  TEXT;
BEGIN
  SELECT premium_until, premium_tier INTO v_until, v_tier
    FROM public.profiles WHERE id = p_user;
  IF v_until IS NULL OR v_until <= now() THEN
    RETURN 'none';
  END IF;
  -- A live premium date with no tier is a pre-tier subscriber the
  -- grandfathering above has not reached (or a row written by an older
  -- build). Treat as 'plus' — they are certainly paying for something.
  RETURN COALESCE(NULLIF(v_tier, ''), 'plus');
EXCEPTION WHEN undefined_column OR undefined_table THEN
  RETURN 'none';
END;
$fn$;

REVOKE ALL ON FUNCTION public.call_premium_tier(UUID)
  FROM PUBLIC, anon, authenticated;


-- The two ceilings, in seconds, for whichever tier this member holds.
-- One place, so call_preflight and call_my_usage cannot disagree about
-- somebody's allowance — which they would have, being two copies of the
-- same CASE expression in two functions 900 lines apart.
CREATE OR REPLACE FUNCTION public.call_daily_cap_seconds(p_user UUID)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT (CASE public.call_premium_tier(p_user)
    WHEN 'pro'  THEN public.call_cfg_int('call.pro_daily_minutes',  720)
    WHEN 'plus' THEN public.call_cfg_int('call.plus_daily_minutes', 360)
    ELSE             public.call_cfg_int('call.free_daily_minutes', 120)
  END) * 60;
$$;

CREATE OR REPLACE FUNCTION public.call_monthly_cap_seconds(p_user UUID)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT (CASE public.call_premium_tier(p_user)
    WHEN 'pro'  THEN public.call_cfg_int('call.pro_monthly_minutes',  9000)
    WHEN 'plus' THEN public.call_cfg_int('call.plus_monthly_minutes', 4500)
    ELSE             public.call_cfg_int('call.free_monthly_minutes', 1500)
  END) * 60;
$$;

REVOKE ALL ON FUNCTION public.call_daily_cap_seconds(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.call_monthly_cap_seconds(UUID)
  FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  8. call_preflight — reproduced from patch_261 with tier-aware caps
--
--  Only the quota block changed. Everything above it is byte-for-byte
--  what patch_261 shipped; it is restated in full because CREATE OR
--  REPLACE has no way to edit part of a body, and a diff against
--  patch_261 is the review this deserves.
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
  --
  -- CHANGED BY patch_268: three ceilings, not two. The old code was a
  -- boolean premium check inlined here and again in call_my_usage.
  v_dmax := public.call_daily_cap_seconds(p_user);
  v_mmax := public.call_monthly_cap_seconds(p_user);

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
--  9. call_my_usage — the Calls tab header
--
--  `premium` stays a BOOLEAN in the payload so an older build keeps
--  working unchanged, and `tier` is added beside it. The app reads the
--  boolean today; the tier is there for the upgrade line.
-- ---------------------------------------------------------------------

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
  v_tier  TEXT;
BEGIN
  IF v_me IS NULL THEN RETURN 'null'::jsonb; END IF;
  SELECT today_seconds, month_seconds INTO v_today, v_month
    FROM public.call_usage_seconds(v_me);
  v_tier := public.call_premium_tier(v_me);
  RETURN jsonb_build_object(
    'today_seconds',  v_today,
    'month_seconds',  v_month,
    'daily_limit_seconds',   public.call_daily_cap_seconds(v_me),
    'monthly_limit_seconds', public.call_monthly_cap_seconds(v_me),
    'premium', v_tier <> 'none',
    'tier',    v_tier);
END;
$$;

DO $$
DECLARE fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY['call_my_usage()'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', fn);
  END LOOP;
END;
$$;


-- ---------------------------------------------------------------------
--  10. Config
--
--  Every one of these is an UPDATE away from being changed again, with
--  no deploy and no app update. That is the point of app_config.
-- ---------------------------------------------------------------------

INSERT INTO public.app_config (key, value) VALUES
  -- Tiered call ceilings. `premium_*` is left in place untouched: this
  -- patch stops reading it, but deleting a row an older build might
  -- still be running against buys nothing.
  ('call.plus_daily_minutes',    '360'),
  ('call.plus_monthly_minutes',  '4500'),
  ('call.pro_daily_minutes',     '720'),
  ('call.pro_monthly_minutes',   '9000')
ON CONFLICT (key) DO NOTHING;

-- A full minute of ringing (founder, 25 Aug 2026 — it was 45 seconds).
-- It is what the phone networks and WhatsApp both settled on, and it is
-- the difference between reaching somebody whose phone is in another
-- room and not. CallConfig.ringTimeout carries the same number as its
-- offline fallback.
--
-- UPDATE, not INSERT ... DO NOTHING: the row already exists and the
-- whole point is to change it.
UPDATE public.app_config SET value = '60'
 WHERE key = 'call.ring_timeout_seconds';

-- Advent AI, for the tier split that is NOT yet wired up — see the
-- header. Seeded now so that patch is a one-line change per call site
-- rather than a config migration as well.
INSERT INTO public.app_config (key, value) VALUES
  ('ai_plus_monthly_units', '100')
ON CONFLICT (key) DO NOTHING;


-- =====================================================================
--  VERIFY (run by hand after applying)
--
--    -- 1. The column exists, is readable, and is NOT writable.
--    SELECT column_name, is_nullable FROM information_schema.columns
--     WHERE table_name = 'profiles' AND column_name = 'premium_tier';
--
--    SELECT grantee, privilege_type
--      FROM information_schema.column_privileges
--     WHERE table_name = 'profiles' AND column_name = 'premium_tier';
--    -- expect: authenticated / SELECT, and NOTHING with UPDATE.
--
--    -- 2. The self-grant is refused. Run as a normal member:
--    UPDATE public.profiles SET premium_tier = 'pro' WHERE id = auth.uid();
--    SELECT premium_tier FROM public.profiles WHERE id = auth.uid();
--    -- expect: unchanged. The UPDATE reports success; the trigger snaps
--    -- it back. That is the same shape as the premium_until guard.
--
--    -- 3. Existing subscribers were grandfathered.
--    SELECT id, premium_until, premium_tier FROM public.profiles
--     WHERE premium_until > now();
--    -- expect: every row 'pro' until its subscription renews.
--
--    -- 4. Ceilings move with the tier.
--    SELECT public.call_premium_tier(id),
--           public.call_daily_cap_seconds(id) / 60 AS daily_minutes
--      FROM public.profiles WHERE premium_until > now() LIMIT 5;
--    -- expect: pro / 720.
--
--    -- 5. Ringing is a minute.
--    SELECT value FROM public.app_config
--     WHERE key = 'call.ring_timeout_seconds';   -- expect 60
-- =====================================================================
