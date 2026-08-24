-- =====================================================================
--  PATCH 253 — iPhone fundraiser (the $99 Apple Developer Program fee)
--
--  Adventist Super App ships on Android. Publishing the iOS build needs
--  an Apple Developer Program membership, which is $99/year. This patch
--  is the backend for a single, dismissible home-feed card that says so
--  and lets members chip in if they want to.
--
--  ## The one rule that shapes every decision below
--
--  **The client never decides how much has been raised.** The Flutter
--  app can create a PENDING pledge and nothing else. The total comes
--  from a SECURITY DEFINER function that sums CONFIRMED rows only, and
--  a row only becomes confirmed when the founder — who is the person
--  actually watching the EcoCash line — says the money arrived.
--
--  Concretely, a malicious client cannot:
--    * insert a confirmed row      → BEFORE INSERT trigger forces
--                                    status='pending' and nulls the
--                                    confirmation columns, whatever the
--                                    payload said;
--    * update its own row to confirmed → there is no UPDATE policy at
--                                    all, for anyone;
--    * change the amount after the fact → same, no UPDATE policy;
--    * touch somebody else's pledge → INSERT policy pins user_id to
--                                    auth.uid(), SELECT policy to own
--                                    rows;
--    * inflate the goal or the total → both come from the server.
--
--  ## Why there is no in-app payment
--
--  Money moves OUTSIDE the app, exactly like public.DonateScreen /
--  lib/screens/donate/donate_screen.dart already does: EcoCash direct
--  transfer, or WhatsApp/email to arrange another method. That is
--  deliberate and it is what keeps the build shippable:
--
--    * Google Play — Play Billing is mandatory for in-app digital
--      purchases. Donations are explicitly outside that, PROVIDED they
--      unlock nothing.
--    * App Store — 3.2.1 permits collecting donations, but not through
--      in-app purchase, and they must not gate functionality.
--
--  So the hard invariant, same as the donate screen's: **a contribution
--  must never unlock a feature, a badge, or content.** The moment it
--  buys something this stops being a donation and becomes an unbilled
--  in-app purchase on both stores.
--
--  ## Configurable, so a campaign change is a dashboard edit
--
--  Goal, currency, suggested amounts, status and the campaign key all
--  live in app_config (patch_091). Nothing is hard-coded in Dart — see
--  lib/services/fundraiser_service.dart, which reads these and falls
--  back to safe defaults so a typo in one row can never take the home
--  screen down.
--
--  IDEMPOTENT: yes. Tables are IF NOT EXISTS, config rows are upserts,
--  functions are CREATE OR REPLACE, policies are dropped first.
-- =====================================================================


-- ---------------------------------------------------------------------
--  SECTION 1 — Configuration
--
--  `fundraiser_campaign_key` is the version token. Bumping it starts a
--  NEW campaign: dismissals and contributions are both keyed by it, so
--  a member who dismissed the iPhone card is not silently opted out of
--  whatever comes next, and last campaign's money does not count toward
--  the new goal.
-- ---------------------------------------------------------------------
INSERT INTO public.app_config (key, value) VALUES
  ('fundraiser_campaign_key',   'ios_launch_2026'),

  -- active | paused | completed
  --
  --   active     — the card asks for support.
  --   paused     — the card hides entirely. Use when the campaign is
  --                mid-review, or the founder simply does not want to
  --                be asking this week.
  --   completed  — the card switches to the thank-you state and STOPS
  --                asking. Set automatically-in-effect once the goal is
  --                met (see fundraiser_status), and settable by hand to
  --                close a campaign early.
  ('fundraiser_status',         'active'),

  -- Cents, always. $99.00 Apple Developer Program membership.
  -- Integer cents rather than a numeric dollar amount because every
  -- arithmetic path here (percent, remaining, sum) is exact in integers
  -- and lossy in floats, and this number is shown to members.
  ('fundraiser_goal_cents',     '9900'),
  ('fundraiser_currency',       'USD'),

  -- The chips on the contribution screen, cents, comma-separated.
  -- $1 / $3 / $5 / $10 — plus a custom field the app always offers.
  ('fundraiser_amounts_cents',  '100,300,500,1000')
ON CONFLICT (key) DO NOTHING;
-- DO NOTHING, not DO UPDATE: re-running this patch must not reset a
-- campaign the founder has since edited in the dashboard.


-- ---------------------------------------------------------------------
--  SECTION 2 — Contributions
--
--  One row per pledge. `amount_cents` as inserted by the client is a
--  STATED INTENTION and is treated as untrusted; the amount that counts
--  is whatever the founder confirms actually arrived, which is why
--  fundraiser_confirm_contribution takes an amount of its own.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fundraiser_contributions (
  id             BIGSERIAL PRIMARY KEY,
  campaign_key   TEXT NOT NULL,

  -- SET NULL, not CASCADE: if a member deletes their account the money
  -- they gave still happened, and deleting the row would silently make
  -- the public total go DOWN. Anonymising it keeps the arithmetic
  -- honest and keeps nothing personal.
  user_id        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,

  amount_cents   INTEGER NOT NULL CHECK (amount_cents > 0
                                         AND amount_cents <= 100000000),
  currency       TEXT NOT NULL DEFAULT 'USD',

  -- 'ecocash' — sent directly to the EcoCash line.
  -- 'other'   — arranged over WhatsApp/email (bank transfer, cash, a
  --             different wallet). The founder records what happened.
  method         TEXT NOT NULL DEFAULT 'ecocash'
                 CHECK (method IN ('ecocash', 'other')),

  status         TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'confirmed', 'rejected')),

  -- The member's own note: an EcoCash transaction reference, or "sent
  -- from my sister's line". Free text, capped, never rendered as HTML.
  reference      TEXT CHECK (reference IS NULL OR char_length(reference) <= 200),

  -- Why a pledge was rejected, for the founder's own records. Never
  -- shown verbatim to the member.
  admin_note     TEXT CHECK (admin_note IS NULL OR char_length(admin_note) <= 500),

  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  confirmed_at   TIMESTAMPTZ,
  confirmed_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- The index the total actually uses: partial on confirmed rows, so
-- summing a campaign never scans the pending backlog.
CREATE INDEX IF NOT EXISTS idx_fundraiser_contrib_confirmed
  ON public.fundraiser_contributions (campaign_key)
  WHERE status = 'confirmed';

-- The founder's review queue.
CREATE INDEX IF NOT EXISTS idx_fundraiser_contrib_pending
  ON public.fundraiser_contributions (campaign_key, created_at DESC)
  WHERE status = 'pending';

-- "My contributions" on the fundraiser screen.
CREATE INDEX IF NOT EXISTS idx_fundraiser_contrib_user
  ON public.fundraiser_contributions (user_id, created_at DESC);


-- ---------------------------------------------------------------------
--  The trigger that makes the client's opinion irrelevant.
--
--  RLS decides WHICH rows you may insert; it cannot stop you putting
--  status='confirmed' in one of them. A WITH CHECK could, but it would
--  only reject the request — and every future column added to this
--  table would need remembering in it. Clamping in a BEFORE trigger is
--  the version that stays correct when someone adds a column in 2027.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_force_pending()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- service_role (the founder's dashboard / a future payment webhook)
  -- is allowed to insert an already-confirmed row. auth.uid() is NULL
  -- there, and RLS does not apply, so this branch is unreachable from
  -- the app.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.status       := 'pending';
  NEW.confirmed_at := NULL;
  NEW.confirmed_by := NULL;
  NEW.admin_note   := NULL;
  NEW.created_at   := NOW();
  -- Pin the owner too, belt and braces with the RLS policy.
  NEW.user_id      := auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fundraiser_force_pending
  ON public.fundraiser_contributions;
CREATE TRIGGER trg_fundraiser_force_pending
  BEFORE INSERT ON public.fundraiser_contributions
  FOR EACH ROW EXECUTE FUNCTION public.fundraiser_force_pending();


ALTER TABLE public.fundraiser_contributions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS fundraiser_contrib_insert_own
  ON public.fundraiser_contributions;
CREATE POLICY fundraiser_contrib_insert_own
  ON public.fundraiser_contributions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS fundraiser_contrib_read_own
  ON public.fundraiser_contributions;
CREATE POLICY fundraiser_contrib_read_own
  ON public.fundraiser_contributions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_super_admin());

-- No UPDATE policy and no DELETE policy, for anybody. Confirming and
-- rejecting go through the SECURITY DEFINER functions in section 4,
-- which is the only path that can change a total. Do not add one.

GRANT SELECT, INSERT ON public.fundraiser_contributions TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.fundraiser_contributions_id_seq
  TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 3 — Dismissals
--
--  "Do not show me this again", stored against the ACCOUNT rather than
--  the device so it follows the member to a new phone. The app also
--  mirrors it into its local Hive cache so the card disappears instantly
--  and stays gone offline — the server row is the durable copy, not the
--  fast one.
--
--  Keyed by campaign so a future campaign starts fresh.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fundraiser_dismissals (
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  campaign_key TEXT NOT NULL,
  dismissed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, campaign_key)
);

ALTER TABLE public.fundraiser_dismissals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS fundraiser_dismissals_own ON public.fundraiser_dismissals;
CREATE POLICY fundraiser_dismissals_own
  ON public.fundraiser_dismissals
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.fundraiser_dismissals TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 4 — The read the app makes
--
--  ONE call returns everything the card and the screen need. It is one
--  round trip on purpose: this runs during home-screen bootstrap, and
--  a fundraising card is not worth three requests.
--
--  SECURITY DEFINER because `raised_cents` must be computed from rows
--  the caller cannot see (other members' contributions). Only the
--  aggregate escapes — never another member's row.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_status()
RETURNS TABLE (
  campaign_key    TEXT,
  status          TEXT,
  goal_cents      INTEGER,
  raised_cents    BIGINT,
  remaining_cents BIGINT,
  currency        TEXT,
  amounts_cents   TEXT,
  supporters      INTEGER,
  dismissed       BOOLEAN,
  my_pending      INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_key       TEXT;
  v_status    TEXT;
  v_goal      INTEGER;
  v_currency  TEXT;
  v_amounts   TEXT;
  v_raised    BIGINT;
  v_supporters INTEGER;
  v_dismissed BOOLEAN;
  v_pending   INTEGER;
BEGIN
  -- Every read is COALESCEd to a working default. A missing or
  -- mistyped config row must degrade to "a sane campaign", never to a
  -- NULL that makes the app divide by zero.
  SELECT COALESCE(value, 'ios_launch_2026') INTO v_key
    FROM public.app_config WHERE key = 'fundraiser_campaign_key';
  v_key := COALESCE(v_key, 'ios_launch_2026');

  SELECT COALESCE(value, 'active') INTO v_status
    FROM public.app_config WHERE key = 'fundraiser_status';
  v_status := COALESCE(v_status, 'active');
  IF v_status NOT IN ('active', 'paused', 'completed') THEN
    v_status := 'active';
  END IF;

  SELECT COALESCE(NULLIF(regexp_replace(value, '\D', '', 'g'), '')::INTEGER, 9900)
    INTO v_goal
    FROM public.app_config WHERE key = 'fundraiser_goal_cents';
  -- A goal of zero would make every percentage a division by zero AND
  -- make the campaign permanently "complete". Floor it.
  v_goal := GREATEST(COALESCE(v_goal, 9900), 1);

  SELECT COALESCE(value, 'USD') INTO v_currency
    FROM public.app_config WHERE key = 'fundraiser_currency';
  v_currency := COALESCE(v_currency, 'USD');

  SELECT COALESCE(value, '100,300,500,1000') INTO v_amounts
    FROM public.app_config WHERE key = 'fundraiser_amounts_cents';
  v_amounts := COALESCE(NULLIF(TRIM(v_amounts), ''), '100,300,500,1000');

  -- CONFIRMED ONLY. This single WHERE clause is the whole security
  -- model of the progress bar.
  SELECT COALESCE(SUM(c.amount_cents), 0),
         COUNT(DISTINCT COALESCE(c.user_id::TEXT, 'anon:' || c.id))
    INTO v_raised, v_supporters
    FROM public.fundraiser_contributions c
   WHERE c.campaign_key = v_key
     AND c.status = 'confirmed';

  SELECT EXISTS (
    SELECT 1 FROM public.fundraiser_dismissals d
     WHERE d.user_id = auth.uid() AND d.campaign_key = v_key
  ) INTO v_dismissed;

  SELECT COUNT(*)::INTEGER INTO v_pending
    FROM public.fundraiser_contributions c
   WHERE c.campaign_key = v_key
     AND c.user_id = auth.uid()
     AND c.status = 'pending';

  -- The goal being met COMPLETES the campaign without anyone editing a
  -- config row. The founder can still say 'paused', and 'paused' wins:
  -- a deliberate pause is a stronger statement than an arithmetic one.
  IF v_status = 'active' AND v_raised >= v_goal THEN
    v_status := 'completed';
  END IF;

  RETURN QUERY SELECT
    v_key,
    v_status,
    v_goal,
    v_raised,
    GREATEST(v_goal::BIGINT - v_raised, 0),
    v_currency,
    v_amounts,
    COALESCE(v_supporters, 0),
    COALESCE(v_dismissed, FALSE),
    COALESCE(v_pending, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fundraiser_status() TO authenticated;


-- ---------------------------------------------------------------------
--  Record a pledge.
--
--  Wrapped in a function rather than left as a bare INSERT so the app
--  never has to know the current campaign key — it would have to be
--  told, and then a stale client could file money against a finished
--  campaign. Resolving it server-side makes that impossible.
--
--  Returns the new row's id so the app can show "we have your note".
--  Returns NULL when the campaign is not accepting anything, which the
--  app renders as a friendly "this campaign has closed" rather than an
--  error.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_record_pledge(
  p_amount_cents INTEGER,
  p_method       TEXT DEFAULT 'ecocash',
  p_reference    TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_key    TEXT;
  v_status TEXT;
  v_open   INTEGER;
  v_id     BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'fundraiser_record_pledge: sign in first';
  END IF;

  SELECT s.campaign_key, s.status INTO v_key, v_status
    FROM public.fundraiser_status() s;

  -- Not 'active' means paused or already funded. Either way we are not
  -- taking any more, and section 10 of the brief is explicit: a
  -- completed campaign stops asking.
  IF v_status <> 'active' THEN
    RETURN NULL;
  END IF;

  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'fundraiser_record_pledge: amount must be positive';
  END IF;

  -- A pledge is a note-to-self about money moving outside the app, so
  -- the ceiling only has to stop nonsense, not fraud. $10,000.
  IF p_amount_cents > 1000000 THEN
    RAISE EXCEPTION 'fundraiser_record_pledge: amount too large';
  END IF;

  -- Rate limit, of the boring sort: a member with five unconfirmed
  -- pledges outstanding is either confused or scripting. Neither is
  -- helped by a sixth.
  SELECT COUNT(*) INTO v_open
    FROM public.fundraiser_contributions
   WHERE user_id = auth.uid()
     AND campaign_key = v_key
     AND status = 'pending';
  IF v_open >= 5 THEN
    RAISE EXCEPTION 'fundraiser_record_pledge: too many pending';
  END IF;

  INSERT INTO public.fundraiser_contributions
    (campaign_key, user_id, amount_cents, method, reference)
  VALUES (
    v_key,
    auth.uid(),
    p_amount_cents,
    CASE WHEN p_method IN ('ecocash', 'other') THEN p_method ELSE 'ecocash' END,
    LEFT(NULLIF(TRIM(COALESCE(p_reference, '')), ''), 200)
  )
  RETURNING id INTO v_id;

  -- Tell the founder there is something to check on the EcoCash line.
  --
  -- This is the ONE notification this feature creates, it goes to super
  -- admins only, and it is operational: nobody can confirm a transfer
  -- they were never told about. It is emphatically NOT the reminder
  -- push the brief forbids — no member ever receives a notification
  -- from this feature, and there are no scheduled or repeat sends.
  INSERT INTO public.notifications (user_id, title, body, type, reference_type, reference_id)
  SELECT
    p.id,
    'Someone offered to help with iPhone',
    'A member says they are sending '
      || TRIM(TO_CHAR(p_amount_cents / 100.0, 'FM999999990.00'))
      || ' toward the iPhone campaign. Check the line, then confirm it '
      || 'so it counts toward the goal.',
    'fundraiser',
    'fundraiser_contribution',
    v_id::TEXT
  FROM public.profiles p
  WHERE p.is_super_admin = TRUE;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fundraiser_record_pledge(INTEGER, TEXT, TEXT)
  TO authenticated;


-- ---------------------------------------------------------------------
--  Confirm — the only thing in this patch that can move the total.
--
--  Takes its own amount because the pledge is what the member SAID and
--  this is what the founder SAW. They differ often enough to matter:
--  someone pledges $5 and sends $3, or rounds up. Passing NULL keeps
--  the pledged amount.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_confirm_contribution(
  p_id           BIGINT,
  p_amount_cents INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_amount INTEGER;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'fundraiser_confirm_contribution: super admin only';
  END IF;

  SELECT amount_cents INTO v_amount
    FROM public.fundraiser_contributions WHERE id = p_id;
  IF v_amount IS NULL THEN
    RETURN FALSE;
  END IF;

  IF p_amount_cents IS NOT NULL THEN
    IF p_amount_cents <= 0 OR p_amount_cents > 1000000 THEN
      RAISE EXCEPTION 'fundraiser_confirm_contribution: bad amount';
    END IF;
    v_amount := p_amount_cents;
  END IF;

  UPDATE public.fundraiser_contributions
     SET status       = 'confirmed',
         amount_cents = v_amount,
         confirmed_at = NOW(),
         confirmed_by = auth.uid()
   WHERE id = p_id
     AND status <> 'confirmed';

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fundraiser_confirm_contribution(BIGINT, INTEGER)
  TO authenticated;


-- ---------------------------------------------------------------------
--  Reject. Rejected rows are kept, not deleted — a pledge that never
--  arrived is still a thing the founder may need to look back at.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_reject_contribution(
  p_id   BIGINT,
  p_note TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'fundraiser_reject_contribution: super admin only';
  END IF;

  UPDATE public.fundraiser_contributions
     SET status     = 'rejected',
         admin_note = LEFT(NULLIF(TRIM(COALESCE(p_note, '')), ''), 500)
   WHERE id = p_id
     AND status <> 'rejected';

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fundraiser_reject_contribution(BIGINT, TEXT)
  TO authenticated;


-- ---------------------------------------------------------------------
--  The founder's review queue, joined to a name so the dashboard does
--  not need a second query.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_list_pending()
RETURNS TABLE (
  id           BIGINT,
  user_id      UUID,
  full_name    TEXT,
  amount_cents INTEGER,
  method       TEXT,
  reference    TEXT,
  created_at   TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'fundraiser_list_pending: super admin only';
  END IF;

  RETURN QUERY
    SELECT c.id, c.user_id, p.full_name, c.amount_cents, c.method,
           c.reference, c.created_at
      FROM public.fundraiser_contributions c
      LEFT JOIN public.profiles p ON p.id = c.user_id
     WHERE c.status = 'pending'
     ORDER BY c.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fundraiser_list_pending() TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 5 — Dismissal, as one call
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fundraiser_dismiss()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_key TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT COALESCE(value, 'ios_launch_2026') INTO v_key
    FROM public.app_config WHERE key = 'fundraiser_campaign_key';

  INSERT INTO public.fundraiser_dismissals (user_id, campaign_key)
  VALUES (auth.uid(), COALESCE(v_key, 'ios_launch_2026'))
  ON CONFLICT (user_id, campaign_key) DO NOTHING;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fundraiser_dismiss() TO authenticated;


-- =====================================================================
--  VERIFICATION
-- =====================================================================
-- 1. Fresh campaign reads as active at zero:
--      SELECT * FROM public.fundraiser_status();
--      -- ios_launch_2026 | active | 9900 | 0 | 9900 | USD | 100,300,500,1000 | 0 | f | 0
--
-- 2. A pledge does NOT move the total, and lands as pending:
--      SELECT public.fundraiser_record_pledge(500, 'ecocash', 'TXN123');
--      SELECT raised_cents, my_pending FROM public.fundraiser_status();
--      -- expect: 0 | 1        <- the whole point
--
-- 3. The client cannot confirm itself. As an ordinary member:
--      UPDATE public.fundraiser_contributions SET status = 'confirmed';
--      -- expect: 0 rows (no UPDATE policy exists)
--      INSERT INTO public.fundraiser_contributions
--        (campaign_key, user_id, amount_cents, status)
--        VALUES ('ios_launch_2026', auth.uid(), 9900, 'confirmed');
--      SELECT status FROM public.fundraiser_contributions ORDER BY id DESC LIMIT 1;
--      -- expect: pending      <- trigger clamped it
--
-- 4. Confirming as super admin moves it, in the amount that ARRIVED:
--      SELECT public.fundraiser_confirm_contribution(<id>, 300);
--      SELECT raised_cents, remaining_cents FROM public.fundraiser_status();
--      -- expect: 300 | 9600
--
-- 5. Hitting the goal completes the campaign with no config edit:
--      -- confirm rows totalling 9900, then
--      SELECT status FROM public.fundraiser_status();
--      -- expect: completed
--      SELECT public.fundraiser_record_pledge(100);
--      -- expect: NULL (not accepting any more)
--
-- 6. Dismissal follows the account:
--      SELECT public.fundraiser_dismiss();
--      SELECT dismissed FROM public.fundraiser_status();   -- t
--      -- sign in on another device as the same user: still t
-- =====================================================================
