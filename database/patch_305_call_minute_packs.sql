-- =====================================================================
--  PATCH 305 — call-minute packs (one-off purchases)
--  STATUS: APPLIED 3 Nov 2026 (by Claude via the Supabase connector).
--  Verified in a rolled-back run: a free member's daily cap went 120 -> 420
--  with a 300-min pack; a replayed token added nothing; after 100/150/160
--  minutes of calls the pack held 300/270/260 minutes.
--
--  Owner, 3 Nov 2026: "put feature for premium for more call minutes —
--  another way to earn money". Premium already raises the daily/monthly
--  call allowance; packs are for members who won't take a subscription.
--
--    call_minutes_300   +300 minutes (5 h),  valid 30 days
--    call_minutes_1200  +1200 minutes (20 h), valid 30 days
--
--  How a pack is spent: ONLY after the plan's own allowance (daily or
--  monthly) is used up. Every second a member talks beyond their plan's
--  cap comes out of their oldest unexpired pack. So Premium members never
--  burn pack minutes while plan minutes remain, and an unused pack simply
--  expires after 30 days.
--
--    * call_daily_cap_seconds / call_monthly_cap_seconds now = plan + the
--      member's unexpired pack balance (call_start, the heartbeat and
--      call_my_usage all read these, so nothing else needed changing).
--    * The plan-only caps keep their old bodies as call_plan_*_cap_seconds.
--    * An AFTER trigger on call_usage_daily spends packs by exactly the
--      seconds that went over the plan cap.
--    * Packs are written ONLY by grant_call_minutes(), service role only,
--      from the verify-boost Edge Function after Google Play confirms the
--      purchase. Idempotent on the purchase token.
--
--  CLAUDE.md checklist: no profiles column. The new trigger is AFTER
--  INSERT/UPDATE (no DELETE, returns NULL as AFTER triggers do).
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.call_minute_packs (
  id                bigserial PRIMARY KEY,
  user_id           uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id        text NOT NULL,
  minutes           integer NOT NULL CHECK (minutes > 0),
  remaining_seconds integer NOT NULL CHECK (remaining_seconds >= 0),
  purchased_at      timestamptz NOT NULL DEFAULT now(),
  expires_at        timestamptz NOT NULL,
  purchase_token    text NOT NULL UNIQUE,
  order_id          text
);
CREATE INDEX IF NOT EXISTS call_minute_packs_user_live
  ON public.call_minute_packs (user_id, expires_at);

ALTER TABLE public.call_minute_packs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.call_minute_packs FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.call_minute_packs TO authenticated;
CREATE POLICY call_minute_packs_own_read ON public.call_minute_packs
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Plan-only caps (the old bodies, unchanged).
CREATE OR REPLACE FUNCTION public.call_plan_daily_cap_seconds(p_user uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT (CASE
    WHEN public.call_premium_tier(p_user) IN ('pro', 'business')
      THEN public.call_cfg_int('call.pro_daily_minutes',  720)
    WHEN public.call_premium_tier(p_user) = 'plus'
      THEN public.call_cfg_int('call.plus_daily_minutes', 360)
    ELSE public.call_cfg_int('call.free_daily_minutes', 120)
  END) * 60;
$function$;

CREATE OR REPLACE FUNCTION public.call_plan_monthly_cap_seconds(p_user uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT (CASE
    WHEN public.call_premium_tier(p_user) IN ('pro', 'business')
      THEN public.call_cfg_int('call.pro_monthly_minutes',  9000)
    WHEN public.call_premium_tier(p_user) = 'plus'
      THEN public.call_cfg_int('call.plus_monthly_minutes', 4500)
    ELSE public.call_cfg_int('call.free_monthly_minutes', 1500)
  END) * 60;
$function$;

-- Unexpired pack balance.
CREATE OR REPLACE FUNCTION public.call_pack_seconds(p_user uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM(remaining_seconds), 0)::integer
    FROM public.call_minute_packs
   WHERE user_id = p_user AND expires_at > now() AND remaining_seconds > 0;
$function$;

-- The caps everything else reads: plan + packs.
CREATE OR REPLACE FUNCTION public.call_daily_cap_seconds(p_user uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.call_plan_daily_cap_seconds(p_user)
       + public.call_pack_seconds(p_user);
$function$;

CREATE OR REPLACE FUNCTION public.call_monthly_cap_seconds(p_user uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.call_plan_monthly_cap_seconds(p_user)
       + public.call_pack_seconds(p_user);
$function$;

-- Spend packs by exactly the seconds that went over the plan cap.
CREATE OR REPLACE FUNCTION public.call_spend_packs()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old      integer := CASE WHEN TG_OP = 'UPDATE' THEN COALESCE(OLD.seconds, 0) ELSE 0 END;
  v_delta    integer := COALESCE(NEW.seconds, 0) - v_old;
  v_dcap     integer;
  v_mcap     integer;
  v_month    integer;
  v_d_over   integer;
  v_m_over   integer;
  v_spend    integer;
  v_pack     record;
  v_take     integer;
BEGIN
  IF v_delta <= 0 THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.call_minute_packs
                  WHERE user_id = NEW.user_id AND expires_at > now()
                    AND remaining_seconds > 0) THEN
    RETURN NULL;
  END IF;

  v_dcap := public.call_plan_daily_cap_seconds(NEW.user_id);
  v_mcap := public.call_plan_monthly_cap_seconds(NEW.user_id);
  SELECT COALESCE(SUM(seconds), 0)::integer INTO v_month
    FROM public.call_usage_daily
   WHERE user_id = NEW.user_id
     AND day >= date_trunc('month', NEW.day)::date
     AND day <  (date_trunc('month', NEW.day) + interval '1 month')::date;

  v_d_over := GREATEST(0, NEW.seconds - v_dcap) - GREATEST(0, v_old - v_dcap);
  v_m_over := GREATEST(0, v_month - v_mcap)
            - GREATEST(0, (v_month - v_delta) - v_mcap);
  v_spend  := GREATEST(v_d_over, v_m_over);

  FOR v_pack IN
    SELECT id, remaining_seconds FROM public.call_minute_packs
     WHERE user_id = NEW.user_id AND expires_at > now()
       AND remaining_seconds > 0
     ORDER BY expires_at, id
     FOR UPDATE
  LOOP
    EXIT WHEN v_spend <= 0;
    v_take := LEAST(v_pack.remaining_seconds, v_spend);
    UPDATE public.call_minute_packs
       SET remaining_seconds = remaining_seconds - v_take
     WHERE id = v_pack.id;
    v_spend := v_spend - v_take;
  END LOOP;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_call_spend_packs
  AFTER INSERT OR UPDATE OF seconds ON public.call_usage_daily
  FOR EACH ROW EXECUTE FUNCTION public.call_spend_packs();

-- Granting a pack: service role only (verify-boost), idempotent on token.
CREATE OR REPLACE FUNCTION public.grant_call_minutes(
  p_user uuid, p_product text, p_minutes integer, p_days integer,
  p_token text, p_order text)
 RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_expires timestamptz;
BEGIN
  IF p_minutes NOT IN (300, 1200) OR p_days <> 30 THEN
    RAISE EXCEPTION 'CALL_PACK_BAD_SKU';
  END IF;
  INSERT INTO public.call_minute_packs
    (user_id, product_id, minutes, remaining_seconds, expires_at,
     purchase_token, order_id)
  VALUES (p_user, p_product, p_minutes, p_minutes * 60,
          now() + make_interval(days => p_days), p_token, p_order)
  ON CONFLICT (purchase_token) DO NOTHING
  RETURNING expires_at INTO v_expires;
  IF v_expires IS NULL THEN
    SELECT expires_at INTO v_expires FROM public.call_minute_packs
     WHERE purchase_token = p_token;
  END IF;
  RETURN v_expires;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.grant_call_minutes(uuid, text, integer, integer, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.call_spend_packs() FROM PUBLIC, anon, authenticated;

-- call_my_usage: also report the pack balance and its soonest expiry.
CREATE OR REPLACE FUNCTION public.call_my_usage()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'tier',    v_tier,
    'pack_seconds', public.call_pack_seconds(v_me),
    'pack_expires_at', (SELECT min(expires_at) FROM public.call_minute_packs
                         WHERE user_id = v_me AND expires_at > now()
                           AND remaining_seconds > 0));
END;
$function$;

COMMIT;
