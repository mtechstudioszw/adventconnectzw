-- patch_309 — $1 "Verified" plan and $1 Advent AI question pack
-- (3 Nov 2026). APPLIED 3 Nov 2026 via migration; verified with rolled-back tests.
--
-- Owner: sell single features for about a dollar — "someone may only need
-- the ID check" — alongside the bundles.
--
-- 1. VERIFIED, US$1/month: a SEPARATE subscription product,
--    `verified_monthly`. It switches on the gold tick (after the same ID
--    check a super admin approves) and NOTHING else.
--
--    Deliberately not a new premium_tier. Ads, call allowances, the AI
--    allowance and quiz rewards all treat "premium_until is in the
--    future" as "gets every Plus perk"; a $1 tier riding on premium_until
--    would have handed out Plus for $1 anywhere one of those checks was
--    missed. So it gets its own date, `profiles.verified_until`, and
--    sync_premium_until now keeps the two products apart: Premium is
--    computed from every subscription EXCEPT verified_monthly, and
--    verified_until from verified_monthly alone.
--
--    The tick rule (refresh_paid_perks): approved ID check AND (any paid
--    Premium level OR a live Verified plan OR super admin). The hourly
--    expire-paid-perks job already re-runs that rule, so a lapsed $1 plan
--    loses the tick within the hour even if no store event arrives.
--
--    verify-purchase needs no new code to accept it — it asks Google about
--    a subscription by its token, whatever the product. Only its receipt
--    text changes (deployed with this patch).
--
-- 2. ADVENT AI QUESTION PACK, US$1 one-time: `ai_questions_50`, verified
--    by verify-boost like the call packs. A third pool, `bonus`, spent
--    only after the free and Premium pools, and never reset monthly —
--    a member who paid for 50 questions keeps them until used.
--
-- CLAUDE.md checklist for touching `profiles`:
--   1. The privilege guard snaps verified_until back (INSERT and UPDATE).
--   2. GRANT SELECT (verified_until) — authenticated reads profiles by
--      column grants only. No UPDATE grant: only the server writes it.
--   3. No table-level grant touched.
--   4. No new BEFORE DELETE trigger.

BEGIN;

-- =================================================== 1. Verified plan

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verified_until timestamptz;

GRANT SELECT (verified_until) ON public.profiles TO authenticated;

CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  -- No JWT = the service role (edge functions) or a DB-internal caller
  -- such as handle_new_user(). The only path allowed to grant anything.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- patch 288: a row a signed-in caller INSERTS starts with nothing.
  IF TG_OP = 'INSERT' THEN
    NEW.is_super_admin    := FALSE;
    NEW.is_verified       := FALSE;
    NEW.is_verified_admin := FALSE;
    NEW.is_banned         := FALSE;
    NEW.is_business       := FALSE;
    NEW.account_type      := 'member';
    NEW.premium_until     := NULL;
    NEW.premium_tier      := NULL;
    NEW.verified_until    := NULL;   -- patch 309
    RETURN NEW;
  END IF;

  -- Premium is BOUGHT, never self-assigned, so it covers super admins
  -- too. premium_until says whether, premium_tier says which, and
  -- verified_until (patch 309) is the separate $1 Verified plan.
  NEW.premium_until  := OLD.premium_until;
  NEW.premium_tier   := OLD.premium_tier;
  NEW.verified_until := OLD.verified_until;

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

  -- patch 267: account_type's CHECK allows 'super_admin'.
  NEW.account_type   := OLD.account_type;

  -- `is_business` can move TRUE during the auto-approve RPC; otherwise
  -- snap it back to whatever it was before.
  IF current_setting('app.auto_approving_business', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_business := OLD.is_business;
  END IF;

  -- patch 188: the gold tick is DERIVED, never self-assigned.
  IF current_setting('app.recomputing_verified_admin', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_verified_admin := OLD.is_verified_admin;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_premium_until(p_user uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_until    TIMESTAMPTZ;
  v_tier     TEXT;
  v_verified TIMESTAMPTZ;
BEGIN
  -- Statuses that keep access: active, in_grace (Google is retrying the
  -- card and asks that access continue), cancelled (auto-renew off, the
  -- period is paid for). Everything else grants nothing.
  --
  -- patch 309: Premium is every product EXCEPT the $1 Verified plan,
  -- which must never count as a Premium level.
  SELECT public.premium_tier_for_base_plan(s.base_plan_id)
    INTO v_tier
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND COALESCE(s.product_id, 'premium_monthly') <> 'verified_monthly'
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL
   ORDER BY public.premium_tier_rank(
              public.premium_tier_for_base_plan(s.base_plan_id)) DESC,
            s.current_period_end DESC
   LIMIT 1;

  SELECT MAX(s.current_period_end)
    INTO v_until
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND COALESCE(s.product_id, 'premium_monthly') <> 'verified_monthly'
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL;

  SELECT MAX(s.current_period_end)
    INTO v_verified
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND s.product_id = 'verified_monthly'
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL;

  UPDATE public.profiles
     SET premium_until  = v_until,
         premium_tier   = CASE WHEN v_until IS NULL THEN NULL ELSE v_tier END,
         verified_until = v_verified
   WHERE id = p_user;

  PERFORM public.refresh_paid_perks(p_user);

  RETURN v_until;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_paid_perks(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tier     text;
  v_until    timestamptz;
  v_super    boolean;
  v_verified boolean;
  v_latest   text;
BEGIN
  SELECT CASE WHEN p.premium_until > now()
              THEN COALESCE(p.premium_tier, 'plus') END,
         p.premium_until,
         COALESCE(p.is_super_admin, false),
         COALESCE(p.verified_until > now(), false)
    INTO v_tier, v_until, v_super, v_verified
    FROM public.profiles p
   WHERE p.id = p_user;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- The member's own tick: approved ID check AND (any paid Premium level
  -- OR the $1 Verified plan, patch 309). The official team account keeps
  -- its tick as a super admin. Members who never applied are untouched.
  SELECT r.status INTO v_latest
    FROM public.verification_requests r
   WHERE r.user_id = p_user AND r.kind = 'person'
   ORDER BY (r.status = 'approved') DESC, r.created_at DESC
   LIMIT 1;

  IF v_latest = 'approved' THEN
    UPDATE public.profiles
       SET is_verified = (v_tier IS NOT NULL OR v_verified OR v_super)
     WHERE id = p_user
       AND is_verified IS DISTINCT FROM
           (v_tier IS NOT NULL OR v_verified OR v_super);
  ELSIF v_latest = 'revoked' THEN
    UPDATE public.profiles SET is_verified = false
     WHERE id = p_user AND is_verified;
  END IF;

  -- Page ticks: approved ID check AND the creator holds Business.
  -- (The $1 plan is for the member's own tick only.)
  UPDATE public.pages pg
     SET is_verified = (v_tier = 'business' OR v_super)
    FROM public.verification_requests r
   WHERE r.user_id = p_user AND r.kind = 'page' AND r.status = 'approved'
     AND pg.id = r.page_id
     AND pg.is_verified IS DISTINCT FROM (v_tier = 'business' OR v_super);

  UPDATE public.pages pg
     SET is_verified = false
    FROM public.verification_requests r
   WHERE r.user_id = p_user AND r.kind = 'page' AND r.status = 'revoked'
     AND pg.id = r.page_id AND pg.is_verified
     AND NOT EXISTS (SELECT 1 FROM public.verification_requests a
                      WHERE a.page_id = r.page_id AND a.status = 'approved');

  -- Business: the member's approved shop is a Featured store for as
  -- long as the plan runs. Hand-featured shops (featured_until NULL)
  -- are never touched.
  IF v_tier = 'business' THEN
    UPDATE public.sellers
       SET featured = true, featured_until = v_until
     WHERE auth_user_id = p_user AND status = 'approved'
       AND (featured IS DISTINCT FROM true
            OR featured_until IS DISTINCT FROM v_until);
  ELSE
    UPDATE public.sellers
       SET featured = false, featured_until = NULL
     WHERE auth_user_id = p_user AND featured_until IS NOT NULL;
  END IF;
END;
$function$;

-- ============================================== 2. AI question pack

ALTER TABLE public.ai_accounts
  ADD COLUMN IF NOT EXISTS bonus_units integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_spent integer NOT NULL DEFAULT 0;

-- The ledger learns the new pool and the new kind of entry.
ALTER TABLE public.ai_ledger DROP CONSTRAINT IF EXISTS ai_ledger_kind_chk;
ALTER TABLE public.ai_ledger ADD CONSTRAINT ai_ledger_kind_chk
  CHECK (kind = ANY (ARRAY['free_grant', 'allowance', 'spend', 'refund',
                           'adjust', 'purchase']));
DO $$
DECLARE c text;
BEGIN
  -- The pool check was created unnamed; find it by what it says.
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.ai_ledger'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%pool%'
  LOOP
    EXECUTE format('ALTER TABLE public.ai_ledger DROP CONSTRAINT %I', c);
  END LOOP;
END $$;
ALTER TABLE public.ai_ledger ADD CONSTRAINT ai_ledger_pool_chk
  CHECK (pool = ANY (ARRAY['free', 'allowance', 'bonus']));

-- One row per Play purchase, so a replayed token never credits twice.
CREATE TABLE IF NOT EXISTS public.ai_pack_purchases (
  purchase_token text PRIMARY KEY,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id     text NOT NULL,
  units          integer NOT NULL CHECK (units > 0),
  order_id       text,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_pack_purchases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ai_pack_purchases FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.grant_ai_questions(
  p_user uuid, p_product text, p_units integer, p_token text, p_order text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_new boolean;
BEGIN
  IF p_product <> 'ai_questions_50' OR p_units <> 50 THEN
    RAISE EXCEPTION 'AI_PACK_BAD_SKU';
  END IF;
  PERFORM public.ai_account_ensure(p_user);

  INSERT INTO public.ai_pack_purchases
    (purchase_token, user_id, product_id, units, order_id)
  VALUES (p_token, p_user, p_product, p_units, p_order)
  ON CONFLICT (purchase_token) DO NOTHING
  RETURNING true INTO v_new;

  IF v_new THEN
    UPDATE public.ai_accounts
       SET bonus_units = bonus_units + p_units
     WHERE user_id = p_user;
    INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
    VALUES (p_user, 'purchase', p_units, 'bonus',
            'Bought ' || p_units || ' questions');
  END IF;

  RETURN (SELECT bonus_units - bonus_spent FROM public.ai_accounts
           WHERE user_id = p_user);
END;
$function$;

-- Spend: free first, then the Premium allowance, then purchased questions
-- (which never reset, so they are the last to be used).
CREATE OR REPLACE FUNCTION public.ai_spend_unit(p_user uuid, p_cost_micros bigint DEFAULT 0, p_conversation_id uuid DEFAULT NULL::uuid, p_message_id bigint DEFAULT NULL::bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row  public.ai_accounts;
  v_pool TEXT;
  v_day  DATE := (NOW() AT TIME ZONE 'utc')::DATE;
  v_cost BIGINT := GREATEST(COALESCE(p_cost_micros, 0), 0);
BEGIN
  PERFORM public.ai_sync_allowance(p_user);

  SELECT * INTO v_row FROM public.ai_accounts
   WHERE user_id = p_user FOR UPDATE;

  IF NOT FOUND OR v_row.blocked THEN
    RETURN NULL;
  END IF;

  IF (v_row.free_units_granted - v_row.free_units_spent) > 0
     AND public.ai_free_pool_open() THEN
    v_pool := 'free';
    UPDATE public.ai_accounts
       SET free_units_spent = free_units_spent + 1,
           cost_micros_total = cost_micros_total + v_cost
     WHERE user_id = p_user;

  ELSIF (v_row.allowance_units - v_row.allowance_spent) > 0 THEN
    v_pool := 'allowance';
    UPDATE public.ai_accounts
       SET allowance_spent = allowance_spent + 1,
           cost_micros_total = cost_micros_total + v_cost
     WHERE user_id = p_user;

  ELSIF (v_row.bonus_units - v_row.bonus_spent) > 0 THEN
    -- patch 309: questions the member bought.
    v_pool := 'bonus';
    UPDATE public.ai_accounts
       SET bonus_spent = bonus_spent + 1,
           cost_micros_total = cost_micros_total + v_cost
     WHERE user_id = p_user;

  ELSE
    RETURN NULL;
  END IF;

  INSERT INTO public.ai_ledger (
    user_id, kind, units, pool, cost_micros, conversation_id, message_id
  ) VALUES (
    p_user, 'spend', -1, v_pool, v_cost, p_conversation_id, p_message_id
  );

  INSERT INTO public.ai_spend_daily (day, cost_micros, free_cost_micros, messages)
  VALUES (v_day, v_cost, CASE WHEN v_pool = 'free' THEN v_cost ELSE 0 END, 1)
  ON CONFLICT (day) DO UPDATE
     SET cost_micros = public.ai_spend_daily.cost_micros + v_cost,
         free_cost_micros = public.ai_spend_daily.free_cost_micros
           + CASE WHEN v_pool = 'free' THEN v_cost ELSE 0 END,
         messages = public.ai_spend_daily.messages + 1;

  RETURN v_pool;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ai_refund_unit(p_user uuid, p_pool text, p_conversation_id uuid DEFAULT NULL::uuid, p_message_id bigint DEFAULT NULL::bigint, p_note text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_pool = 'free' THEN
    UPDATE public.ai_accounts
       SET free_units_spent = GREATEST(free_units_spent - 1, 0)
     WHERE user_id = p_user;
  ELSIF p_pool = 'allowance' THEN
    UPDATE public.ai_accounts
       SET allowance_spent = GREATEST(allowance_spent - 1, 0)
     WHERE user_id = p_user;
  ELSIF p_pool = 'bonus' THEN
    UPDATE public.ai_accounts
       SET bonus_spent = GREATEST(bonus_spent - 1, 0)
     WHERE user_id = p_user;
  ELSE
    RETURN FALSE;
  END IF;

  INSERT INTO public.ai_ledger (
    user_id, kind, units, pool, conversation_id, message_id, note
  ) VALUES (
    p_user, 'refund', 1, p_pool, p_conversation_id, p_message_id,
    COALESCE(p_note, 'Answer failed')
  );

  RETURN TRUE;
END;
$function$;

-- Balance: purchased questions count toward what is left and toward
-- "can ask". Same columns as before (they are folded into
-- total_remaining), so the app and the advent-ai function need no change
-- to honour them.
CREATE OR REPLACE FUNCTION public.ai_my_balance_for(p_user uuid)
 RETURNS TABLE(free_remaining integer, allowance_remaining integer, total_remaining integer, allowance_units integer, is_premium boolean, free_pool_open boolean, resets_on date, can_use boolean, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row     public.ai_accounts;
  v_open    BOOLEAN;
  v_prem    BOOLEAN;
  v_state   TEXT;
  v_free    INTEGER := 0;
  v_allow   INTEGER := 0;
  v_bonus   INTEGER := 0;
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

    v_bonus := GREATEST(v_row.bonus_units - v_row.bonus_spent, 0);
  ELSE
    v_free := CASE WHEN v_open THEN v_grant ELSE 0 END;
    IF v_prem THEN
      v_allow := public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER;
    END IF;
  END IF;

  IF v_state <> 'live' THEN
    v_reason := 'service_suspended';
  ELSIF v_row.user_id IS NOT NULL AND v_row.blocked THEN
    v_reason := 'blocked';
  ELSIF v_allow > 0 OR (v_free > 0 AND v_open) OR v_bonus > 0 THEN
    v_reason := 'ok';
  ELSIF v_prem THEN
    v_reason := 'out_of_allowance';
  ELSIF NOT v_open AND (v_row.user_id IS NULL OR v_row.free_units_granted = 0) THEN
    v_reason := 'free_pool_closed';
  ELSE
    v_reason := 'out_of_free';
  END IF;

  RETURN QUERY SELECT
    GREATEST(v_free, 0),
    GREATEST(v_allow, 0),
    GREATEST(v_free, 0) + GREATEST(v_allow, 0) + v_bonus,
    CASE WHEN v_prem
      THEN public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER
      ELSE 0 END,
    v_prem,
    v_open,
    v_reset,
    (v_reason = 'ok'),
    v_reason;
END;
$function$;

REVOKE ALL ON FUNCTION public.grant_ai_questions(uuid, text, integer, text, text)
  FROM PUBLIC, anon, authenticated;

COMMIT;
