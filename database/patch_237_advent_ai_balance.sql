-- =====================================================================
--  PATCH 237 — Advent AI, part 2: allowance, ledger, entitlement
--
--  Part 1 (patch_236) stores the conversation. This decides who may
--  spend, and records every unit that moves.
--
--  ## The model (founder decision, 23 Aug 2026)
--
--    Free member  — 20 messages, ONCE, ever. A taste of what it does.
--    Premium      — 500 messages per calendar month, reset on the 1st.
--
--  Advent AI is a Premium feature with a free sample. It is NOT sold as
--  credit top-ups; there are no consumable products and no separate
--  funding purchase. Entitlement comes from `profiles.premium_until`,
--  which is written ONLY by supabase/functions/verify-purchase after
--  Google Play confirms a real subscription. That means this feature
--  inherits an already-verified billing path rather than adding a second
--  one.
--
--  ### Why an allowance at all, if Premium is a subscription
--
--  Because a subscription is unlimited by default and this feature is
--  not free to serve. A $3/month subscription nets ~$2.10-2.55 after
--  store fees; at the worst-case cost of one message on
--  gemini-2.5-flash-lite (~$0.0013, bounded by ai_max_output_tokens and
--  ai_max_context_tokens) a member would have to send ~1,600 messages a
--  month before costing more than they pay. No human does that. A script
--  does. The 500/month allowance costs at most $0.65 against $2.10+ of
--  income, so the margin holds even if every subscriber exhausts it —
--  and one abusive account cannot run up the founder's card.
--
--  ## Two units, and they are not interchangeable
--
--  MESSAGE UNITS are what a member sees and spends. One completed
--  exchange costs exactly one unit, whatever its length. Flat-rate is
--  safe because the worst case is bounded (above), and it is what makes
--  "18 messages left" mean exactly eighteen messages. Do not "improve"
--  this into variable pricing — the honesty is the feature.
--
--  COST MICROS are millionths of a US dollar of REAL provider spend,
--  recorded per message from the provider's own usage report. Members
--  never see them. They exist so the global ceilings can be enforced
--  against money actually leaving the founder's card rather than against
--  unit estimates that could drift.
--
--  ## Two pools
--
--    free      — the one-time sample. Capped GLOBALLY by
--                ai_global_free_pool_micros, so the total spend on
--                people who have never paid is bounded no matter how
--                many accounts are created.
--    allowance — the Premium monthly entitlement. NEVER capped globally.
--                A paying member is unaffected by the free pool running
--                dry or by the daily ceiling; both exist to protect the
--                founder from non-paying usage, and a subscriber has
--                already paid.
--
--  Spend order is free-first, so the sample is used before the
--  entitlement — a member who subscribes mid-sample is not charged twice.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Per-member account
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_accounts (
  user_id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- The one-time free sample.
  free_units_granted INTEGER NOT NULL DEFAULT 0,
  free_units_spent   INTEGER NOT NULL DEFAULT 0,

  -- The Premium monthly allowance. Both reset together when the calendar
  -- month rolls over — see ai_sync_allowance().
  allowance_units    INTEGER NOT NULL DEFAULT 0,
  allowance_spent    INTEGER NOT NULL DEFAULT 0,

  -- First day (UTC) of the calendar month the current allowance is for.
  -- NULL means "never had one".
  allowance_period   DATE,

  -- Real provider spend attributable to this member. Diagnostics and
  -- abuse investigation only; never shown to anyone.
  cost_micros_total  BIGINT NOT NULL DEFAULT 0,

  -- Bars a member from the AI specifically (abuse), without touching
  -- their Adventist Super App account. Normal app use continues.
  blocked            BOOLEAN NOT NULL DEFAULT FALSE,
  blocked_reason     TEXT,

  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT ai_accounts_free_sane CHECK (
    free_units_granted >= 0 AND free_units_spent >= 0
    AND free_units_spent <= free_units_granted
  ),
  CONSTRAINT ai_accounts_allowance_sane CHECK (
    allowance_units >= 0 AND allowance_spent >= 0
    AND allowance_spent <= allowance_units
  )
);

-- The CHECK constraints are the real defence. An UPDATE that tried to
-- spend more than was granted fails loudly rather than going negative and
-- silently handing out free usage.

DROP TRIGGER IF EXISTS ai_accounts_touch_trg ON public.ai_accounts;
CREATE TRIGGER ai_accounts_touch_trg
  BEFORE UPDATE ON public.ai_accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------
--  Ledger — every unit in and out, append-only
--
--  NOT cascaded from ai_conversations. A member deleting a conversation
--  must not erase the record of what was spent on it, or the balance
--  stops reconciling and a billing dispute has no evidence. The FK to
--  auth.users DOES cascade: a deleted account has no balance to
--  reconcile, and keeping the rows would be holding data on someone who
--  left.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_ledger (
  id           BIGSERIAL PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  --   free_grant  — the one-time sample
  --   allowance   — a Premium month opening
  --   spend       — one completed exchange
  --   refund      — a spend reversed (provider failed after the debit)
  --   adjust      — manual correction by the founder, always with a note
  kind         TEXT NOT NULL,

  -- Signed. Positive adds to the balance, negative removes.
  units        INTEGER NOT NULL,

  -- Which pool moved: 'free' or 'allowance'.
  pool         TEXT NOT NULL,

  -- Real provider cost of this row when it is a spend; zero otherwise.
  cost_micros  BIGINT NOT NULL DEFAULT 0,

  -- Nullable, and deliberately NOT foreign keys: the conversation may be
  -- deleted later and this row must survive it.
  conversation_id UUID,
  message_id      BIGINT,

  note         TEXT,
  meta         JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT ai_ledger_kind_chk
    CHECK (kind IN ('free_grant', 'allowance', 'spend', 'refund', 'adjust')),
  CONSTRAINT ai_ledger_pool_chk
    CHECK (pool IN ('free', 'allowance')),
  CONSTRAINT ai_ledger_cost_nonneg CHECK (cost_micros >= 0)
);

CREATE INDEX IF NOT EXISTS ai_ledger_user_idx
  ON public.ai_ledger (user_id, id DESC);

-- Drives the global free ceiling. Partial: only free spends matter for
-- it, and they are a small slice of the table.
CREATE INDEX IF NOT EXISTS ai_ledger_free_spend_idx
  ON public.ai_ledger (created_at)
  WHERE kind = 'spend' AND pool = 'free';

-- ---------------------------------------------------------------------
--  Global spend, per day
--
--  A running total, so the ceilings are one indexed read rather than an
--  aggregate over the whole ledger on every request. `day` is UTC.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_spend_daily (
  day              DATE PRIMARY KEY,
  cost_micros      BIGINT NOT NULL DEFAULT 0,
  free_cost_micros BIGINT NOT NULL DEFAULT 0,
  messages         INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------
--  Config reader
--
--  Every limit is an app_config row so it can change from the dashboard
--  without an app release. A missing key falls back to the supplied
--  default rather than erroring — a typo in a config key must never take
--  the whole feature down.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_config_int(p_key TEXT, p_default BIGINT)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(
    (SELECT NULLIF(regexp_replace(value, '[^0-9-]', '', 'g'), '')::BIGINT
       FROM public.app_config WHERE key = p_key),
    p_default
  );
$$;

-- ---------------------------------------------------------------------
--  Is the global free pool still open?
--
--  Guards the founder's card against people who have never paid. Two
--  independent ceilings, both in real dollars, both applying to FREE
--  usage only:
--
--    ai_global_free_pool_micros — lifetime total the founder will spend
--      on non-paying members. Default $10.
--    ai_global_daily_cap_micros — per UTC day, so a bug or a spike
--      cannot drain the lifetime pool in one afternoon.
--
--  Premium allowance usage is never measured against either.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_free_pool_open()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_lifetime_cap BIGINT := public.ai_config_int('ai_global_free_pool_micros', 10000000);
  v_daily_cap    BIGINT := public.ai_config_int('ai_global_daily_cap_micros', 500000);
  v_lifetime     BIGINT;
  v_today        BIGINT;
BEGIN
  SELECT COALESCE(SUM(free_cost_micros), 0) INTO v_lifetime FROM public.ai_spend_daily;
  IF v_lifetime >= v_lifetime_cap THEN
    RETURN FALSE;
  END IF;

  SELECT COALESCE(free_cost_micros, 0) INTO v_today
    FROM public.ai_spend_daily WHERE day = (NOW() AT TIME ZONE 'utc')::DATE;

  RETURN COALESCE(v_today, 0) < v_daily_cap;
END;
$$;

-- ---------------------------------------------------------------------
--  Is this member entitled to the Premium allowance?
--
--  Reads the SAME column the ads and every other premium gate read, so
--  there is exactly one definition of "premium" in the system and the AI
--  cannot disagree with the rest of the app. Written only by
--  verify-purchase after Google Play confirms the subscription.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_is_premium(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(
    (SELECT p.premium_until > NOW() FROM public.profiles p WHERE p.id = p_user),
    FALSE
  );
$$;

-- ---------------------------------------------------------------------
--  Open (or roll over) this member's monthly allowance.
--
--  Called before every spend decision. Three cases:
--    * not premium         — allowance is zeroed. A lapsed subscriber
--                            keeps nothing; the sample is separate and
--                            is not touched.
--    * premium, new month  — allowance reset to the configured figure.
--    * premium, same month — left exactly as it is. Unused messages do
--                            NOT roll over; that is what makes the cost
--                            per subscriber bounded per month rather
--                            than accumulating into one big spike.
--
--  The period is the calendar month in UTC, so it resets on the 1st for
--  everyone. Simple to explain in the UI and impossible to game by
--  re-subscribing.
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
BEGIN
  SELECT * INTO v_row FROM public.ai_accounts WHERE user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

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
--  Ensure an account exists, granting the one-time sample.
--
--  Deliberately NOT wired into handle_new_user(). CLAUDE.md's standing
--  rule is that touching a shared signup trigger is how three separate
--  production bugs happened in one day, and this feature does not need
--  that risk. The account is created lazily on first contact with Advent
--  AI, which also means members who never open it never get a row.
--
--  Idempotent by construction: the PK makes a second insert a no-op, so
--  the sample can only ever be granted once per account.
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
    v_grant := public.ai_config_int('ai_free_grant_units', 20)::INTEGER;

    -- If the global free pool is already exhausted the account is still
    -- created — the member can subscribe — but no sample is granted.
    IF NOT public.ai_free_pool_open() THEN
      v_grant := 0;
    END IF;

    INSERT INTO public.ai_accounts (user_id, free_units_granted)
    VALUES (v_user, v_grant)
    ON CONFLICT (user_id) DO NOTHING;

    IF v_grant > 0 THEN
      INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
      VALUES (v_user, 'free_grant', v_grant, 'free', 'Welcome sample');
    END IF;
  END IF;

  RETURN public.ai_sync_allowance(v_user);
END;
$$;

CREATE OR REPLACE FUNCTION public.ai_account_ensure_self()
RETURNS public.ai_accounts
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$ SELECT * FROM public.ai_account_ensure(auth.uid()); $$;

-- ---------------------------------------------------------------------
--  What the client is allowed to know about its own balance.
--
--  A function rather than a SELECT on ai_accounts, so the client sees
--  derived, safe numbers and never the raw counters. `can_use` and
--  `reason` are computed server-side and are the ONLY answers the app
--  should act on — the client must never decide for itself whether the
--  member may send.
--
--  `reason` vocabulary, mapped 1:1 to a screen in the app:
--    ok                 — go ahead
--    out_of_free        — sample used up, not premium. Offer Premium.
--    out_of_allowance   — premium, this month's messages used. Say when
--                         it resets. Do NOT offer to sell anything.
--    free_pool_closed   — never had a sample; app-wide free pool is dry.
--    blocked            — this account is barred from the AI.
--    service_suspended  — the provider is refusing us. Nobody's fault,
--                         nobody is charged, and funding is hidden.
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
  v_reset   DATE := (date_trunc('month', NOW() AT TIME ZONE 'utc') + INTERVAL '1 month')::DATE;
  v_grant   INTEGER := public.ai_config_int('ai_free_grant_units', 20)::INTEGER;
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
    v_free  := v_row.free_units_granted - v_row.free_units_spent;
    -- Report the allowance this member WOULD have this month. The stored
    -- counters may be a month stale until the next send calls
    -- ai_sync_allowance(); this function is STABLE and must not write,
    -- so it derives instead of correcting.
    IF v_prem THEN
      IF v_row.allowance_period IS DISTINCT FROM
         date_trunc('month', NOW() AT TIME ZONE 'utc')::DATE THEN
        v_allow := public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER;
      ELSE
        v_allow := v_row.allowance_units - v_row.allowance_spent;
      END IF;
    END IF;
  ELSE
    -- No account yet. Report what they WOULD get so the intro screen can
    -- say "you have 20 free messages" before the first send creates it.
    v_free := CASE WHEN v_open THEN v_grant ELSE 0 END;
    IF v_prem THEN
      v_allow := public.ai_config_int('ai_premium_monthly_units', 500)::INTEGER;
    END IF;
  END IF;

  -- Decide, in priority order. The order matters: a suspended service
  -- outranks everything (nobody can send, so no other explanation is
  -- true), and being blocked outranks having credit.
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
    CASE WHEN v_prem THEN v_reset ELSE NULL END,
    (v_reason = 'ok'),
    v_reason;
END;
$$;

-- ---------------------------------------------------------------------
--  Spend one unit. Called ONLY by the edge function (service_role).
--
--  Returns the pool charged, or NULL when nothing could be charged. The
--  caller must treat NULL as "refuse" — this is the authorisation point
--  for the whole feature, and the only one that counts. Whatever the
--  client believes about its own balance is irrelevant here.
--
--  Free-first, then allowance. The row is locked FOR UPDATE so two
--  concurrent requests from the same member cannot both spend the last
--  unit.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_spend_unit(
  p_user            UUID,
  p_cost_micros     BIGINT DEFAULT 0,
  p_conversation_id UUID   DEFAULT NULL,
  p_message_id      BIGINT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_row  public.ai_accounts;
  v_pool TEXT;
  v_day  DATE := (NOW() AT TIME ZONE 'utc')::DATE;
  v_cost BIGINT := GREATEST(COALESCE(p_cost_micros, 0), 0);
BEGIN
  -- Roll the month over first, so a subscriber's 1st-of-the-month send
  -- is served by the new allowance rather than refused on the old one.
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

  ELSE
    RETURN NULL;
  END IF;

  INSERT INTO public.ai_ledger (
    user_id, kind, units, pool, cost_micros, conversation_id, message_id
  ) VALUES (
    p_user, 'spend', -1, v_pool, v_cost, p_conversation_id, p_message_id
  );

  -- Global running totals. `free_cost_micros` is what the ceilings read,
  -- so a Premium message adds to the day's cost for reporting but never
  -- to the pool the founder is protecting.
  INSERT INTO public.ai_spend_daily (day, cost_micros, free_cost_micros, messages)
  VALUES (v_day, v_cost, CASE WHEN v_pool = 'free' THEN v_cost ELSE 0 END, 1)
  ON CONFLICT (day) DO UPDATE
     SET cost_micros = public.ai_spend_daily.cost_micros + v_cost,
         free_cost_micros = public.ai_spend_daily.free_cost_micros
           + CASE WHEN v_pool = 'free' THEN v_cost ELSE 0 END,
         messages = public.ai_spend_daily.messages + 1;

  RETURN v_pool;
END;
$$;

-- ---------------------------------------------------------------------
--  Give a unit back.
--
--  A member must never pay for an answer they did not get. The edge
--  function debits BEFORE calling the provider (so a crash mid-request
--  cannot leave a free ride) and refunds on every failure path.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_refund_unit(
  p_user UUID,
  p_pool TEXT,
  p_conversation_id UUID DEFAULT NULL,
  p_message_id BIGINT DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_pool = 'free' THEN
    UPDATE public.ai_accounts
       SET free_units_spent = GREATEST(free_units_spent - 1, 0)
     WHERE user_id = p_user;
  ELSIF p_pool = 'allowance' THEN
    UPDATE public.ai_accounts
       SET allowance_spent = GREATEST(allowance_spent - 1, 0)
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
$$;

-- ---------------------------------------------------------------------
--  RLS + grants
--
--  Members read their own account and ledger. They write NOTHING here.
--  Every mutation is SECURITY DEFINER, and the only ones a client may
--  execute are the two that cannot move units in the member's favour.
-- ---------------------------------------------------------------------
ALTER TABLE public.ai_accounts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_ledger      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_spend_daily ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.ai_accounts    FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_ledger      FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_spend_daily FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_accounts_select_own ON public.ai_accounts;
CREATE POLICY ai_accounts_select_own ON public.ai_accounts
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS ai_ledger_select_own ON public.ai_ledger;
CREATE POLICY ai_ledger_select_own ON public.ai_ledger
  FOR SELECT USING (user_id = auth.uid());

-- ai_spend_daily has NO policy at all. It is the founder's own spend
-- across every member — nobody's business but the server's. RLS enabled
-- with no policy denies everything to anon/authenticated; service_role
-- bypasses.

REVOKE ALL ON public.ai_accounts    FROM anon, authenticated;
REVOKE ALL ON public.ai_ledger      FROM anon, authenticated;
REVOKE ALL ON public.ai_spend_daily FROM anon, authenticated;

GRANT SELECT ON public.ai_accounts TO authenticated;
GRANT SELECT ON public.ai_ledger   TO authenticated;

-- Function grants. The rule: a client may ask what it has, and may cause
-- its own account row to exist. It may not spend, refund, or grant.
REVOKE ALL ON FUNCTION public.ai_spend_unit(UUID, BIGINT, UUID, BIGINT)      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ai_refund_unit(UUID, TEXT, UUID, BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ai_config_int(TEXT, BIGINT)                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ai_account_ensure(UUID)                        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ai_sync_allowance(UUID)                        FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.ai_my_balance()           TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_account_ensure_self()  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_free_pool_open()       TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_is_premium(UUID)       TO authenticated;

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- -- Nobody can write a balance:
-- SELECT grantee, privilege_type FROM information_schema.role_table_grants
--  WHERE table_schema='public' AND table_name='ai_accounts'
--    AND grantee IN ('anon','authenticated');
--   -- expect: SELECT only, authenticated only
--
-- -- The spend function is unreachable from a client:
-- SELECT has_function_privilege('authenticated',
--          'public.ai_spend_unit(uuid,bigint,uuid,bigint)', 'EXECUTE');
--   -- expect: false
--
-- -- What a member sees:
-- SELECT * FROM public.ai_my_balance();
--
-- -- Global spend so far — the number protecting the card:
-- SELECT SUM(free_cost_micros)/1000000.0 AS free_dollars,
--        SUM(cost_micros)/1000000.0      AS total_dollars,
--        SUM(messages)                   AS messages
--   FROM public.ai_spend_daily;
-- =====================================================================
