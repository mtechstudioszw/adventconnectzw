-- =====================================================================
--  PATCH 239 — Advent AI: monthly free refill + per-tier model
--
--  Sits on top of the Advent AI core patches (conversations, balance,
--  config). Two changes, both reconciling decisions that were made
--  differently in two places.
--
--  ## Numbering — RESOLVED 23 Aug 2026
--
--  The three Advent AI patches were originally numbered 233/234/235,
--  colliding with committed quiz patches of the same numbers. They have
--  been renumbered, relative order preserved:
--
--    patch_236  advent_ai_core     conversations + messages
--    patch_237  advent_ai_balance  allowance, ledger, entitlement
--    patch_238  advent_ai_config   config keys + service state
--    patch_239  (this)             monthly free refill + per-tier model
--
--  Apply in that order.
--
--  ## Change 1 — the free grant refills monthly
--
--  As built, the free sample is granted ONCE per account, for life
--  (`ai_account_ensure` inserts `free_units_granted` and nothing ever
--  raises it again).
--
--  That kills the feature for most of the user base. A member spends
--  ten questions in their first week, cannot afford US$3, and now has no
--  reason to ever open Advent AI again — permanently. The ask then has
--  to land on somebody who used the feature once, months ago, instead of
--  somebody who uses it every month and is running out.
--
--  So: the free grant becomes a monthly refill, on the same calendar
--  boundary as the Premium allowance. The COST of that is still bounded
--  by the two global ceilings that already exist — a refill cannot
--  outrun `ai_global_free_pool_micros` or `ai_global_daily_cap_micros`,
--  because those are enforced against real provider spend rather than
--  against granted units. This raises how OFTEN a free member can come
--  back; it does not raise the maximum the founder can be billed.
--
--  Refills only happen while the free pool is open. A member whose month
--  rolls over during a closed pool gets their refill the next time
--  anything syncs them after it reopens, not a backdated pile of units.
--
--  ## Change 2 — Premium answers on a better model
--
--  `ai_model` is a single key, so every tier answers on
--  gemini-2.5-flash-lite. This adds `ai_model_premium` and leaves
--  `ai_model` as the free/default.
--
--  This is not crippling the free tier to sell the paid one — it is what
--  makes a free tier affordable at all (flash-lite is ~4x cheaper per
--  answer), and it gives Premium a difference members can actually feel.
--  The previous Premium benefit line was "no ads", which is a benefit
--  about removing an annoyance rather than about the thing being bought.
--
--  The edge function must read `ai_model_premium` when
--  `ai_is_premium(user)` and `ai_model` otherwise. Until it does, this
--  key is inert — adding it here is safe and changes nothing on its own.
--
--  ## What this patch does NOT do
--
--  No top-up / bundle products. The brief (§20-24) asked for a "Fund
--  Your Account" system, and it is deliberately not built yet: a
--  consumable IAP is a second billing verification path, and consumables
--  are the harder one to secure (a purchase token must be consumed
--  exactly once; duplicate-grant bugs are the classic exploit against
--  that flow). Subscriptions already run through verify-purchase +
--  play-rtdn, which are live and verified. The ledger's `pool` column
--  already supports a third pool, so adding one later is an INSERT and a
--  branch in ai_spend_unit — not a migration.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Track which month the free grant belongs to.
--
--  NULL means "granted once, under the old for-life rule". Those
--  accounts are adopted on their next sync: the backfill below stamps
--  them with the current period so nobody receives a second grant the
--  instant this patch lands, and the refill begins at the NEXT month
--  boundary. Without that stamp, every existing member would be handed
--  a fresh ten units on deploy.
-- ---------------------------------------------------------------------
ALTER TABLE public.ai_accounts
  ADD COLUMN IF NOT EXISTS free_period DATE;

COMMENT ON COLUMN public.ai_accounts.free_period IS
  'First day (UTC) of the calendar month the current free grant is for. '
  'NULL only for rows created before patch 239; backfilled on deploy.';

UPDATE public.ai_accounts
   SET free_period = date_trunc('month', NOW() AT TIME ZONE 'utc')::DATE
 WHERE free_period IS NULL;

-- ---------------------------------------------------------------------
--  2. Refill the free grant on the month boundary.
--
--  Extends ai_sync_allowance rather than adding a second function, so
--  there is still exactly ONE place that rolls a member's counters over
--  and exactly one FOR UPDATE lock protecting them. A separate refill
--  function would race this one.
--
--  Order inside the function matters: the free refill runs for EVERY
--  member, premium or not, before the premium branch returns early.
--  A subscriber keeps their free units too — they are spent first (see
--  ai_spend_unit's free-first order), so somebody who subscribes
--  mid-sample is not charged for units they already had.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_sync_allowance(p_user UUID)
RETURNS public.ai_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_row     public.ai_accounts;
  v_period  DATE := date_trunc('month', NOW() AT TIME ZONE 'utc')::DATE;
  v_units   INTEGER;
  v_free    INTEGER;
BEGIN
  SELECT * INTO v_row FROM public.ai_accounts WHERE user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- ---- Free refill, for everybody ----------------------------------
  --
  -- Guarded on the global pool: a closed pool must not mint units. The
  -- member simply refills the next time they are synced after it
  -- reopens, which is correct — the pool being shut is exactly the
  -- state in which we do not want to promise more free usage.
  IF v_row.free_period IS DISTINCT FROM v_period
     AND public.ai_free_pool_open()
  THEN
    v_free := public.ai_config_int('ai_free_grant_units', 10)::INTEGER;

    UPDATE public.ai_accounts
       SET free_units_granted = v_free,
           free_units_spent   = 0,
           free_period        = v_period
     WHERE user_id = p_user
    RETURNING * INTO v_row;

    -- 'free_grant', not 'grant' — ai_ledger_kind_chk allows only
    -- free_grant/allowance/spend/refund/adjust, so the obvious spelling
    -- fails the constraint on the first refill.
    INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
    VALUES (p_user, 'free_grant', v_free, 'free',
            'Free refill for ' || to_char(v_period, 'Mon YYYY'));
  END IF;

  -- ---- Premium allowance -------------------------------------------
  IF NOT public.ai_is_premium(p_user) THEN
    IF v_row.allowance_units <> 0 OR v_row.allowance_spent <> 0 THEN
      UPDATE public.ai_accounts
         SET allowance_units = 0, allowance_spent = 0, allowance_period = NULL
       WHERE user_id = p_user
      RETURNING * INTO v_row;
    END IF;
    RETURN v_row;
  END IF;

  IF v_row.allowance_period IS DISTINCT FROM v_period THEN
    v_units := public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER;

    UPDATE public.ai_accounts
       SET allowance_units = v_units,
           allowance_spent = 0,
           allowance_period = v_period
     WHERE user_id = p_user
    RETURNING * INTO v_row;

    INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
    VALUES (p_user, 'allowance', v_units, 'allowance',
            'Premium allowance for ' || to_char(v_period, 'Mon YYYY'));
  END IF;

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------
--  2b. Stamp free_period when the account is first created.
--
--  ai_account_ensure inserts (user_id, free_units_granted) and then
--  calls ai_sync_allowance. Without this, a BRAND NEW account is created
--  with free_period NULL, the sync immediately sees NULL <> this month,
--  and refills it — resetting the counters it just set and writing a
--  second ledger row ("Free refill for...") directly beneath "Welcome
--  sample". The welcome grant becomes meaningless and every new member's
--  ledger opens with a duplicate.
--
--  Only the INSERT changes; the rest is the function from the balance
--  patch. The 20 default is corrected to 10 to match the live config
--  value while we are in here.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_account_ensure(p_user UUID DEFAULT NULL)
RETURNS public.ai_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user  UUID := COALESCE(p_user, auth.uid());
  v_grant INTEGER;
  v_row   public.ai_accounts;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'ai_account_ensure: not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.ai_accounts WHERE user_id = v_user;

  IF NOT FOUND THEN
    v_grant := public.ai_config_int('ai_free_grant_units', 10)::INTEGER;

    -- If the global free pool is already exhausted the account is still
    -- created — the member can subscribe — but no sample is granted.
    IF NOT public.ai_free_pool_open() THEN
      v_grant := 0;
    END IF;

    -- free_period stamped here so the first sync does not re-grant.
    -- When the pool is shut we deliberately leave it NULL: the member
    -- got nothing, and the next sync after the pool reopens should hand
    -- them their first sample rather than making them wait for the 1st.
    INSERT INTO public.ai_accounts (user_id, free_units_granted, free_period)
    VALUES (
      v_user,
      v_grant,
      CASE WHEN v_grant > 0
        THEN date_trunc('month', NOW() AT TIME ZONE 'utc')::DATE
        ELSE NULL END
    )
    ON CONFLICT (user_id) DO NOTHING;

    IF v_grant > 0 THEN
      INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
      VALUES (v_user, 'free_grant', v_grant, 'free', 'Welcome sample');
    END IF;
  END IF;

  RETURN public.ai_sync_allowance(v_user);
END;
$$;

-- ---------------------------------------------------------------------
--  3. ai_my_balance must report the refill the member WOULD get.
--
--  It is STABLE and must not write, so — exactly as it already does for
--  the premium allowance — it derives the post-refill figure rather than
--  correcting the stored counters. Without this, a member returning on
--  the 1st sees "0 questions left" until their first send silently
--  refills them, which reads as the feature being broken.
--
--  Only the free branch changes; everything else is byte-for-byte the
--  function from the balance patch.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_my_balance()
RETURNS TABLE (
  free_remaining      INTEGER,
  allowance_remaining INTEGER,
  total_remaining     INTEGER,
  allowance_units     INTEGER,
  is_premium          BOOLEAN,
  free_pool_open      BOOLEAN,
  resets_on           DATE,
  can_use             BOOLEAN,
  reason              TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user    UUID := auth.uid();
  v_row     public.ai_accounts;
  v_open    BOOLEAN;
  v_prem    BOOLEAN;
  v_state   TEXT;
  v_free    INTEGER := 0;
  v_allow   INTEGER := 0;
  v_reason  TEXT;
  v_period  DATE := date_trunc('month', NOW() AT TIME ZONE 'utc')::DATE;
  v_reset   DATE := (date_trunc('month', NOW() AT TIME ZONE 'utc') + INTERVAL '1 month')::DATE;
  v_grant   INTEGER := public.ai_config_int('ai_free_grant_units', 10)::INTEGER;
BEGIN
  IF v_user IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(value, 'live') INTO v_state
    FROM public.app_config WHERE key = 'ai_service_state';
  v_state := COALESCE(v_state, 'live');

  v_open := public.ai_free_pool_open();
  v_prem := public.ai_is_premium(v_user);

  SELECT * INTO v_row FROM public.ai_accounts WHERE user_id = v_user;

  IF FOUND THEN
    -- A stale free_period means the refill has not been applied yet.
    -- Report what the next sync will grant, not the spent-out figure.
    IF v_row.free_period IS DISTINCT FROM v_period AND v_open THEN
      v_free := v_grant;
    ELSE
      v_free := v_row.free_units_granted - v_row.free_units_spent;
    END IF;

    IF v_prem THEN
      IF v_row.allowance_period IS DISTINCT FROM v_period THEN
        v_allow := public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER;
      ELSE
        v_allow := v_row.allowance_units - v_row.allowance_spent;
      END IF;
    END IF;
  ELSE
    v_free := CASE WHEN v_open THEN v_grant ELSE 0 END;
    IF v_prem THEN
      v_allow := public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER;
    END IF;
  END IF;

  IF v_state <> 'live' THEN
    v_reason := 'service_suspended';
  ELSIF FOUND AND v_row.blocked THEN
    v_reason := 'blocked';
  ELSIF v_allow > 0 THEN
    v_reason := 'ok';
  ELSIF v_free > 0 AND v_open THEN
    v_reason := 'ok';
  ELSIF v_prem THEN
    v_reason := 'out_of_allowance';
  ELSIF NOT v_open AND (NOT FOUND OR v_row.free_units_granted = 0) THEN
    v_reason := 'free_pool_closed';
  ELSE
    v_reason := 'out_of_free';
  END IF;

  RETURN QUERY SELECT
    GREATEST(v_free, 0),
    GREATEST(v_allow, 0),
    GREATEST(v_free, 0) + GREATEST(v_allow, 0),
    CASE WHEN v_prem
      THEN public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER
      ELSE 0 END,
    v_prem,
    v_open,
    -- Free members now DO refill, so they get a reset date too. Showing
    -- "comes back on 1 September" is most of what stops the wall
    -- reading as a permanent lockout.
    v_reset,
    (v_reason = 'ok'),
    v_reason;
END;
$$;

-- ---------------------------------------------------------------------
--  4. Config: the Premium model, and the free grant restated.
--
--  ai_free_grant_units is already '10'. It is re-upserted here only so
--  that this patch is self-contained — the balance patch's function
--  DEFAULT still says 20 in two places, and a reader comparing them
--  should find the live value stated where the refill is defined.
-- ---------------------------------------------------------------------
INSERT INTO public.app_config (key, value) VALUES
  ('ai_free_grant_units', '10'),

  -- Read by the edge function when ai_is_premium(user). Inert until it
  -- does; adding the key changes nothing on its own.
  ('ai_model_premium',    'gemini-2.5-flash')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ---------------------------------------------------------------------
--  5. Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_missing TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'ai_accounts'
       AND column_name  = 'free_period'
  ) THEN
    RAISE EXCEPTION 'patch 239: ai_accounts.free_period missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ai_accounts WHERE free_period IS NULL
  ) THEN
    RAISE EXCEPTION 'patch 239: existing ai_accounts rows were not backfilled';
  END IF;

  SELECT string_agg(k, ', ') INTO v_missing
    FROM unnest(ARRAY['ai_free_grant_units', 'ai_model_premium']) AS k
   WHERE NOT EXISTS (SELECT 1 FROM public.app_config c WHERE c.key = k);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'patch 239: config keys missing: %', v_missing;
  END IF;

  RAISE NOTICE 'patch 239 OK — free refills monthly; ai_model_premium set';
END $$;
