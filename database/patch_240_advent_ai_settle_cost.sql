-- =====================================================================
--  PATCH 240 — Advent AI: cost settlement + a service-role balance read
--
--  Two functions the edge function needs and that do not exist.
--
--  ## 1. The ceiling that never trips
--
--  `ai_spend_unit` records `p_cost_micros` into `ai_spend_daily`, and
--  `ai_free_pool_open()` reads that table to decide whether the free
--  pool is still open. That is the guard standing between an abusive
--  account and the founder's card.
--
--  But the debit happens BEFORE the provider is called — it has to, or a
--  crash mid-request is a free ride — and the real cost is not known
--  until the provider reports usage afterwards. So the only value
--  available at debit time is zero, and with zero:
--
--      free_cost_micros stays 0 forever
--        -> ai_free_pool_open() always returns true
--        -> the global ceiling is present, looks correct, and does
--           nothing at all
--
--  A guard that cannot fire is worse than no guard, because nobody goes
--  looking for it.
--
--  The fix is two-phase: the edge function debits a deliberately
--  PESSIMISTIC estimate (the whole context window in, the whole output
--  cap out), then calls `ai_settle_cost` with what was actually billed.
--  Over-counting between the two is safe — the ceiling trips slightly
--  early. Under-counting is the direction that costs money, so the
--  estimate is never allowed to be optimistic.
--
--  Settlement writes the DIFFERENCE, which is normally negative. It
--  never rewrites history: the original ledger row stands and a
--  correcting `adjust` row is added beside it, so the ledger remains
--  append-only and auditable.
--
--  ## 2. ai_my_balance cannot be used by the edge function
--
--  `ai_my_balance()` reads `auth.uid()`, which is NULL under
--  service_role. The edge function needs the same answer for a named
--  member — to tell a refused send apart from a closed pool, and to
--  return a fresh balance with each answer.
--
--  `ai_my_balance_for(p_user)` is that, and is REVOKEd from clients: a
--  member reading anyone's balance by passing a uuid is exactly the hole
--  the auth.uid() version exists to avoid.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Balance for a named member. service_role only.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_my_balance_for(p_user UUID)
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
  IF p_user IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(value, 'live') INTO v_state
    FROM public.app_config WHERE key = 'ai_service_state';
  v_state := COALESCE(v_state, 'live');

  v_open := public.ai_free_pool_open();
  v_prem := public.ai_is_premium(p_user);

  SELECT * INTO v_row FROM public.ai_accounts WHERE user_id = p_user;

  IF FOUND THEN
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
  ELSIF v_allow > 0 OR (v_free > 0 AND v_open) THEN
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
    v_reset,
    (v_reason = 'ok'),
    v_reason;
END;
$$;

-- ---------------------------------------------------------------------
--  2. Settle an estimated debit against what was actually billed.
--
--  Called once per successful exchange. Safe to call with equal values
--  (writes nothing), and safe to call twice for the same message — the
--  second call finds the correction already present and does nothing,
--  so a retried edge invocation cannot double-correct.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_settle_cost(
  p_user            UUID,
  p_conversation_id UUID,
  p_message_id      BIGINT,
  p_estimate_micros BIGINT,
  p_actual_micros   BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_delta BIGINT;
  v_pool  TEXT;
  v_day   DATE := (NOW() AT TIME ZONE 'utc')::DATE;
BEGIN
  IF p_user IS NULL THEN
    RETURN FALSE;
  END IF;

  v_delta := GREATEST(COALESCE(p_actual_micros, 0), 0)
           - GREATEST(COALESCE(p_estimate_micros, 0), 0);

  IF v_delta = 0 THEN
    RETURN TRUE;
  END IF;

  -- Idempotence: one correction per message, ever.
  IF p_message_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.ai_ledger
     WHERE message_id = p_message_id
       AND kind = 'adjust'
       AND note = 'cost settlement'
  ) THEN
    RETURN TRUE;
  END IF;

  -- Which pool the original spend came from, so the correction lands on
  -- the same one. The most recent spend for this conversation is the
  -- exchange being settled.
  SELECT pool INTO v_pool
    FROM public.ai_ledger
   WHERE user_id = p_user
     AND kind = 'spend'
     AND (p_conversation_id IS NULL OR conversation_id = p_conversation_id)
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_pool IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Append a correction; never rewrite the original row. `units` is 0
  -- because no message unit moved — only money.
  --
  -- `cost_micros` cannot carry the correction: ai_ledger_cost_nonneg
  -- forbids negatives, and the normal settlement IS negative (the
  -- estimate was pessimistic on purpose). Clamping it to 0 would leave
  -- a row saying "an adjustment happened" with no record of by how
  -- much, which defeats the point of an auditable ledger.
  --
  -- So the signed truth goes in `meta`, and cost_micros carries only the
  -- rare positive case. Anything reconciling this ledger against a
  -- provider invoice must read meta->>'delta_micros', not cost_micros.
  INSERT INTO public.ai_ledger (
    user_id, kind, units, pool, cost_micros,
    conversation_id, message_id, note, meta
  ) VALUES (
    p_user, 'adjust', 0, v_pool, GREATEST(v_delta, 0),
    p_conversation_id, p_message_id, 'cost settlement',
    jsonb_build_object(
      'delta_micros',    v_delta,
      'estimate_micros', GREATEST(COALESCE(p_estimate_micros, 0), 0),
      'actual_micros',   GREATEST(COALESCE(p_actual_micros, 0), 0)
    )
  );

  UPDATE public.ai_accounts
     SET cost_micros_total = GREATEST(cost_micros_total + v_delta, 0)
   WHERE user_id = p_user;

  -- The number the ceilings actually read.
  UPDATE public.ai_spend_daily
     SET cost_micros = GREATEST(cost_micros + v_delta, 0),
         free_cost_micros = CASE
           WHEN v_pool = 'free'
             THEN GREATEST(free_cost_micros + v_delta, 0)
           ELSE free_cost_micros END
   WHERE day = v_day;

  RETURN TRUE;
END;
$$;

-- ---------------------------------------------------------------------
--  Grants — both are service_role only.
--
--  ai_my_balance_for takes a uuid, so exposing it to `authenticated`
--  would let any member read any other member's balance by passing
--  their id. That is precisely what the auth.uid() version exists to
--  prevent, and re-opening it here would undo it.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.ai_my_balance_for(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ai_settle_cost(UUID, UUID, BIGINT, BIGINT, BIGINT)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF has_function_privilege('authenticated',
       'public.ai_my_balance_for(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'patch 240: ai_my_balance_for is reachable by authenticated — '
      'any member could read another member''s balance';
  END IF;

  IF has_function_privilege('authenticated',
       'public.ai_settle_cost(uuid,uuid,bigint,bigint,bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'patch 240: ai_settle_cost is reachable by authenticated';
  END IF;

  RAISE NOTICE 'patch 240 OK — settlement + service-role balance read';
END $$;
