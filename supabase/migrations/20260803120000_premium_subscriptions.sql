-- ---------------------------------------------------------------------
--  PREMIUM SUBSCRIPTIONS — schema + the locks that make it a
--  subscription rather than a suggestion.
--
--  Founder decisions encoded here (3 Aug 2026):
--    * Premium is per ADVENT account, not per Google account. It follows
--      the person across devices and survives a phone change.
--    * A store purchase token is claimed by the FIRST Advent account
--      that redeems it and can never be moved to a second one.
--    * Server-side verification only. The client may READ its premium
--      state and may never write it.
--    * Google's grace period keeps access (their card is being retried);
--      a cancellation keeps access until the period already paid for
--      ends; a refund, chargeback, revocation, pause or account hold
--      cuts access off immediately.
--
--  Store-agnostic on purpose. `platform` + `purchase_token` covers Play
--  today and StoreKit later without a migration:
--    Play     -> purchaseToken
--    StoreKit -> originalTransactionId
--  Both are "the store's permanent handle on this subscription".
-- ---------------------------------------------------------------------

-- =====================================================================
--  1. profiles.premium_until — the single flag the whole app reads
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS premium_until TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.premium_until IS
  'Instant premium lapses. Written ONLY by sync_premium_until() from '
  'verified store state. NULL or past = free tier. The app caches this '
  'timestamp so an offline launch still knows, and it expires by itself '
  'so a stale cache can never grant premium forever.';

-- ---------------------------------------------------------------------
--  Make premium_until readable but NOT writable by clients.
--
--  Two facts about this database, both verified rather than assumed:
--
--  1. SELECT on profiles is already granted PER COLUMN (every column
--     carries its own `authenticated=r`). A new column is therefore
--     invisible to the app until granted — so without the GRANT below,
--     PremiumService.refresh() would read null for everybody and no one
--     would ever be premium.
--
--  2. UPDATE, by contrast, is granted at TABLE level, so every new
--     column is client-writable by default. A single REST call —
--     PATCH /profiles?id=eq.<me> {"premium_until":"2099-01-01"} —
--     would buy a lifetime subscription for nothing.
--
--  And the trap that makes (2) awkward: PostgreSQL SILENTLY IGNORES a
--  column-level REVOKE when the underlying grant is table-level. It
--  returns success and changes nothing. The only way to restrict one
--  column is to drop the table-level grant and re-grant every other
--  column explicitly, which is what this block does.
--
--  >>> MAINTENANCE NOTE <<<
--  After this migration, UPDATE on profiles is per-column, matching how
--  SELECT already works here. A column added later is NOT client-
--  writable until it is granted — the failure looks like a swallowed
--  42501, the same shape this project has been bitten by three times.
--  Adding a client-editable profile column now means also running:
--      GRANT UPDATE (new_col) ON public.profiles TO authenticated, anon;
--      GRANT SELECT (new_col) ON public.profiles TO authenticated;
-- ---------------------------------------------------------------------

-- The app must be able to READ its own premium state.
GRANT SELECT (premium_until) ON public.profiles TO authenticated;

-- Rebuild UPDATE as per-column, covering everything except premium_until.
-- Generated from the live column list so the set can't be fat-fingered.
DO $grants$
DECLARE
  cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum)
    INTO cols
    FROM pg_attribute
   WHERE attrelid = 'public.profiles'::regclass
     AND attnum > 0
     AND NOT attisdropped
     AND attname <> 'premium_until';

  EXECUTE 'REVOKE UPDATE ON public.profiles FROM authenticated, anon';
  EXECUTE format(
    'GRANT UPDATE (%s) ON public.profiles TO authenticated, anon', cols);
END
$grants$;

-- =====================================================================
--  2. Belt as well as braces: extend the existing self-grant guard
--
--  The REVOKE above is the hard lock. This trigger is the second one,
--  because the app already learned that a single missing policy is how
--  privileges leak — and it is the guard that survives someone
--  re-running an old GRANT.
-- =====================================================================

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
  NEW.premium_until := OLD.premium_until;

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

-- =====================================================================
--  3. subscriptions — one row per store purchase token
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL
                        REFERENCES public.profiles(id) ON DELETE CASCADE,

  platform            TEXT NOT NULL
                        CHECK (platform IN ('google_play', 'app_store')),
  product_id          TEXT NOT NULL,

  -- Play purchaseToken / StoreKit originalTransactionId.
  purchase_token      TEXT NOT NULL,

  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                          'pending',    -- awaiting verification
                          'active',     -- paid, renewing
                          'in_grace',   -- payment failed, store retrying (KEEPS access)
                          'cancelled',  -- auto-renew off, paid through period_end (KEEPS access)
                          'on_hold',    -- store gave up retrying (NO access)
                          'paused',     -- user paused (NO access)
                          'expired',    -- ran out (NO access)
                          'refunded',   -- money returned (NO access, immediately)
                          'revoked'     -- chargeback / store revoked (NO access, immediately)
                        )),

  -- End of the period the user has actually paid for.
  current_period_end  TIMESTAMPTZ,
  auto_renewing       BOOLEAN NOT NULL DEFAULT TRUE,

  -- Set once, when this token was first redeemed. Never moves.
  linked_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_verified_at    TIMESTAMPTZ,

  -- Last payload the store gave us, for support and for working out
  -- what a surprising state actually meant.
  raw                 JSONB,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One token, one subscription. This is what stops a purchase being
  -- redeemed on a second Advent account.
  CONSTRAINT subscriptions_token_unique UNIQUE (platform, purchase_token)
);

COMMENT ON TABLE public.subscriptions IS
  'Verified store subscriptions. Written ONLY by the service role after '
  'the store has confirmed the purchase. Users may read their own rows.';

CREATE INDEX IF NOT EXISTS subscriptions_user_idx
  ON public.subscriptions (user_id);

-- Lets the renewal sweeper find rows worth re-checking.
CREATE INDEX IF NOT EXISTS subscriptions_period_end_idx
  ON public.subscriptions (current_period_end)
  WHERE status IN ('active', 'in_grace', 'cancelled');

DROP TRIGGER IF EXISTS trg_subscriptions_updated_at ON public.subscriptions;
CREATE TRIGGER trg_subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------
--  A redeemed token belongs to its first account, permanently.
--
--  Without this, the "premium follows the Advent account" decision has a
--  hole: buy once, then sign into a second account and re-verify the
--  same token to move premium across. The unique constraint stops a
--  second ROW; this stops the existing row being re-pointed.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subscriptions_lock_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION
      'A store purchase stays with the account that first redeemed it '
      '(subscription %, platform %).', OLD.id, OLD.platform
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.purchase_token IS DISTINCT FROM OLD.purchase_token THEN
    RAISE EXCEPTION 'purchase_token is immutable (subscription %).', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_subscriptions_lock_owner ON public.subscriptions;
CREATE TRIGGER trg_subscriptions_lock_owner
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.subscriptions_lock_owner();

-- =====================================================================
--  4. subscription_events — append-only history
--
--  Every verification and every store notification lands here. This is
--  what lets the admin dashboard answer "how many subscribers did we
--  gain and lose this week" without guessing from the current state,
--  and what lets support reconstruct a disputed charge.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.subscription_events (
  id              BIGSERIAL PRIMARY KEY,
  subscription_id UUID REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  user_id         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  platform        TEXT NOT NULL,
  -- 'purchased' | 'renewed' | 'grace' | 'hold' | 'paused' | 'restored'
  -- | 'cancelled' | 'expired' | 'refunded' | 'revoked' | 'verify_failed'
  event_type      TEXT NOT NULL,
  from_status     TEXT,
  to_status       TEXT,
  raw             JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS subscription_events_created_idx
  ON public.subscription_events (created_at DESC);
CREATE INDEX IF NOT EXISTS subscription_events_user_idx
  ON public.subscription_events (user_id);

-- =====================================================================
--  5. sync_premium_until — the ONLY thing that writes premium
--
--  Derives profiles.premium_until from verified subscription rows, so
--  the flag can never drift from what the store actually says. Call it
--  after every verification and every store notification.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.sync_premium_until(p_user UUID)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_until TIMESTAMPTZ;
BEGIN
  -- Statuses that keep access:
  --   active    — paid and renewing
  --   in_grace  — the store is retrying a failed payment; Google asks
  --               that access continue, and the user usually fixes it
  --   cancelled — auto-renew is off but the current period is paid for
  -- Everything else (on_hold, paused, expired, refunded, revoked,
  -- pending) grants nothing, which is what makes a refund bite at once.
  SELECT MAX(s.current_period_end)
    INTO v_until
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL;

  UPDATE public.profiles
     SET premium_until = v_until
   WHERE id = p_user;

  RETURN v_until;
END;
$function$;

-- Nobody but the server may call it. SECURITY DEFINER + a client grant
-- would hand out exactly the privilege the rest of this file removes.
REVOKE ALL ON FUNCTION public.sync_premium_until(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_premium_until(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION public.sync_premium_until(UUID) FROM anon;

-- =====================================================================
--  6. RLS — read your own, write nothing
-- =====================================================================

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;

-- A user can see their own subscription (the Premium screen shows the
-- renewal date and state from it).
DROP POLICY IF EXISTS subscriptions_select_own ON public.subscriptions;
CREATE POLICY subscriptions_select_own
  ON public.subscriptions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public.is_super_admin());

-- Support needs the history; the user doesn't.
DROP POLICY IF EXISTS subscription_events_select_admin
  ON public.subscription_events;
CREATE POLICY subscription_events_select_admin
  ON public.subscription_events FOR SELECT
  TO authenticated
  USING (public.is_super_admin());

-- Deliberately NO insert/update/delete policy on either table. The
-- service role bypasses RLS; everyone else has no write path at all.
GRANT SELECT ON public.subscriptions TO authenticated;
GRANT SELECT ON public.subscription_events TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.subscriptions FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.subscription_events
  FROM authenticated, anon;
