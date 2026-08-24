-- =====================================================================
--  PATCH 254 — Fundraiser campaigns as data, and the console that runs
--              them
--
--  Builds on patch_253, which shipped ONE campaign whose copy lived in
--  Dart string literals and whose goal lived in scattered app_config
--  rows. That was right for one campaign and wrong for two: starting a
--  second one would have meant an app release, and it would have
--  carried the iPhone story with it.
--
--  This patch moves the campaign itself into a row. Starting a new one
--  becomes a form in the web console, not a build.
--
--  ## What does NOT change
--
--  Every security property of patch_253 is untouched and re-verified at
--  the bottom of this file:
--
--    * the client still cannot confirm, update or delete a contribution;
--    * `raised_cents` is still SUM(...) WHERE status='confirmed';
--    * the BEFORE INSERT trigger still clamps status to 'pending';
--    * there is still no UPDATE policy and no DELETE policy on
--      fundraiser_contributions, for anybody.
--
--  `fundraiser_status()` keeps its exact signature plus two new columns
--  (title, body). Older app builds select by name and ignore them.
--
--  ## The anti-nagging rule, enforced in SQL
--
--  A card that refills every time it empties is a nag, and the brief
--  this feature was built from forbids exactly that. So:
--
--    * a new campaign is NEVER started automatically. Completing one
--      does not queue another. A human clicks a button.
--    * a member who dismissed ANY campaign is not shown the next one
--      until `fundraiser_new_campaign_cooldown_days` has passed (default
--      30). Dismissing is read as "not interested in this sort of
--      thing", not merely "not interested in this one".
--
--  The second rule is the one that matters. Without it, per-campaign
--  dismissals mean an eager founder can put the card back in front of
--  someone who closed it, weekly, forever, without ever technically
--  ignoring a dismissal.
--
--  IDEMPOTENT: yes.
-- =====================================================================


-- ---------------------------------------------------------------------
--  SECTION 1 — The campaign table
--
--  `key` is the same token app_config.fundraiser_campaign_key points
--  at, and the same token contributions and dismissals are keyed by.
--  Keeping the pointer in app_config rather than a boolean column here
--  means "which campaign is live" stays a single value that cannot
--  disagree with itself — two rows both flagged active is not a state
--  this can reach.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fundraiser_campaigns (
  key            TEXT PRIMARY KEY,
  title          TEXT NOT NULL,
  body           TEXT NOT NULL,
  goal_cents     INTEGER NOT NULL CHECK (goal_cents > 0),
  currency       TEXT NOT NULL DEFAULT 'USD',
  amounts_cents  TEXT NOT NULL DEFAULT '100,300,500,1000',
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active', 'paused', 'completed')),
  thanks_title   TEXT NOT NULL DEFAULT 'We did it',
  thanks_body    TEXT NOT NULL DEFAULT
    'Thank you to everyone who helped. You made it happen.',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  completed_at   TIMESTAMPTZ
);

-- Members never read this table directly; everything reaches them
-- through fundraiser_status(), which is SECURITY DEFINER. Locking it
-- down means a future column (an internal note, a target account
-- number) cannot leak by being added.
ALTER TABLE public.fundraiser_campaigns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fundraiser_campaigns FROM anon, authenticated;


-- ---------------------------------------------------------------------
--  SECTION 2 — Carry the live iPhone campaign into the table
--
--  Reads whatever app_config currently holds rather than re-stating
--  9900 here, so a goal the founder already edited in the dashboard is
--  preserved rather than silently reset.
-- ---------------------------------------------------------------------
INSERT INTO public.fundraiser_campaigns
  (key, title, body, goal_cents, currency, amounts_cents, status,
   thanks_title, thanks_body)
SELECT
  COALESCE((SELECT value FROM public.app_config
             WHERE key = 'fundraiser_campaign_key'), 'ios_launch_2026'),
  'Help us reach iPhone',
  'Adventist Super App is on Android today. We are raising {goal} for the '
    || 'Apple Developer fee so we can publish it for iPhone users too.',
  GREATEST(COALESCE((SELECT NULLIF(regexp_replace(value, '\D', '', 'g'), '')::INTEGER
                       FROM public.app_config
                      WHERE key = 'fundraiser_goal_cents'), 9900), 1),
  COALESCE((SELECT value FROM public.app_config
             WHERE key = 'fundraiser_currency'), 'USD'),
  COALESCE(NULLIF(TRIM((SELECT value FROM public.app_config
                         WHERE key = 'fundraiser_amounts_cents')), ''),
           '100,300,500,1000'),
  COALESCE((SELECT value FROM public.app_config
             WHERE key = 'fundraiser_status'), 'active'),
  'We did it',
  'Thank you to everyone who helped bring Adventist Super App closer to '
    || 'iPhone. You made the publishing fee.'
ON CONFLICT (key) DO NOTHING;

-- The cooldown that stops a new campaign reaching someone who closed
-- the last one. Days.
INSERT INTO public.app_config (key, value) VALUES
  ('fundraiser_new_campaign_cooldown_days', '30')
ON CONFLICT (key) DO NOTHING;


-- ---------------------------------------------------------------------
--  SECTION 3 — fundraiser_status(), now reading the campaign row
--
--  Same contract as patch_253 plus `title` and `body`. app_config stays
--  the fallback for every field, so this function still returns a
--  working campaign if the table is somehow empty.
-- ---------------------------------------------------------------------
-- DROP, not CREATE OR REPLACE. Adding `title` and `body` changes the
-- return type, and Postgres refuses to REPLACE a function whose OUT
-- parameters differ ("cannot change return type of existing function").
--
-- The drop resets the function's ACL to the default, which hands
-- EXECUTE straight back to PUBLIC — the exact hole patch_254 just
-- closed. Section 7 re-revokes it; do not remove that section while
-- this drop exists.
DROP FUNCTION IF EXISTS public.fundraiser_status();

CREATE FUNCTION public.fundraiser_status()
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
  my_pending      INTEGER,
  title           TEXT,
  body            TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_key        TEXT;
  v_c          public.fundraiser_campaigns%ROWTYPE;
  v_status     TEXT;
  v_goal       INTEGER;
  v_currency   TEXT;
  v_amounts    TEXT;
  v_title      TEXT;
  v_body       TEXT;
  v_raised     BIGINT;
  v_supporters INTEGER;
  v_dismissed  BOOLEAN;
  v_pending    INTEGER;
  v_cooldown   INTEGER;
  v_last_dismiss TIMESTAMPTZ;
BEGIN
  SELECT COALESCE(value, 'ios_launch_2026') INTO v_key
    FROM public.app_config WHERE key = 'fundraiser_campaign_key';
  v_key := COALESCE(v_key, 'ios_launch_2026');

  SELECT * INTO v_c FROM public.fundraiser_campaigns WHERE key = v_key;

  IF v_c.key IS NOT NULL THEN
    v_status   := v_c.status;
    v_goal     := v_c.goal_cents;
    v_currency := v_c.currency;
    v_amounts  := v_c.amounts_cents;
    v_title    := v_c.title;
    v_body     := v_c.body;
  ELSE
    -- No row: fall back to patch_253's app_config behaviour verbatim.
    SELECT COALESCE(value, 'active') INTO v_status
      FROM public.app_config WHERE key = 'fundraiser_status';
    SELECT COALESCE(NULLIF(regexp_replace(value, '\D', '', 'g'), '')::INTEGER, 9900)
      INTO v_goal FROM public.app_config WHERE key = 'fundraiser_goal_cents';
    SELECT COALESCE(value, 'USD') INTO v_currency
      FROM public.app_config WHERE key = 'fundraiser_currency';
    SELECT COALESCE(value, '100,300,500,1000') INTO v_amounts
      FROM public.app_config WHERE key = 'fundraiser_amounts_cents';
    v_title := 'Help us reach iPhone';
    v_body  := 'Adventist Super App is on Android today. We are raising '
               || '{goal} for the Apple Developer fee so we can publish it '
               || 'for iPhone users too.';
  END IF;

  v_status   := COALESCE(v_status, 'active');
  IF v_status NOT IN ('active', 'paused', 'completed') THEN
    v_status := 'active';
  END IF;
  v_goal     := GREATEST(COALESCE(v_goal, 9900), 1);
  v_currency := COALESCE(v_currency, 'USD');
  v_amounts  := COALESCE(NULLIF(TRIM(v_amounts), ''), '100,300,500,1000');

  -- CONFIRMED ONLY. Unchanged from patch_253, and still the whole
  -- security model of the progress bar.
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

  -- The cooldown. Someone who closed a PREVIOUS campaign recently is
  -- treated as having closed this one too. Without this, per-campaign
  -- dismissal keys become a way to re-ask indefinitely.
  IF NOT COALESCE(v_dismissed, FALSE) THEN
    SELECT COALESCE(NULLIF(regexp_replace(value, '\D', '', 'g'), '')::INTEGER, 30)
      INTO v_cooldown
      FROM public.app_config
     WHERE key = 'fundraiser_new_campaign_cooldown_days';
    v_cooldown := COALESCE(v_cooldown, 30);

    SELECT MAX(d.dismissed_at) INTO v_last_dismiss
      FROM public.fundraiser_dismissals d
     WHERE d.user_id = auth.uid();

    IF v_last_dismiss IS NOT NULL
       AND v_last_dismiss > NOW() - (v_cooldown || ' days')::INTERVAL THEN
      v_dismissed := TRUE;
    END IF;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_pending
    FROM public.fundraiser_contributions c
   WHERE c.campaign_key = v_key
     AND c.user_id = auth.uid()
     AND c.status = 'pending';

  -- Meeting the goal completes the campaign with no config edit. A
  -- deliberate 'paused' still wins over the arithmetic.
  IF v_status = 'active' AND v_raised >= v_goal THEN
    v_status := 'completed';
  END IF;

  RETURN QUERY SELECT
    v_key, v_status, v_goal, v_raised,
    GREATEST(v_goal::BIGINT - v_raised, 0),
    v_currency, v_amounts,
    COALESCE(v_supporters, 0),
    COALESCE(v_dismissed, FALSE),
    COALESCE(v_pending, 0),
    v_title,
    -- {goal} is substituted server-side so the copy reads correctly in
    -- whatever currency and amount the campaign was created with, and
    -- the client never has to assemble a sentence.
    REPLACE(
      v_body, '{goal}',
      CASE WHEN v_currency = 'USD'
           THEN '$' || CASE WHEN v_goal % 100 = 0
                            THEN (v_goal / 100)::TEXT
                            ELSE to_char(v_goal / 100.0, 'FM999999990.00') END
           ELSE v_currency || ' ' || CASE WHEN v_goal % 100 = 0
                            THEN (v_goal / 100)::TEXT
                            ELSE to_char(v_goal / 100.0, 'FM999999990.00') END
      END);
END;
$$;

REVOKE ALL ON FUNCTION public.fundraiser_status() FROM anon;
GRANT EXECUTE ON FUNCTION public.fundraiser_status() TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 4 — The console's read
--
--  Staff-gated and deliberately richer than the member view: pending
--  money, rejected count, and the campaign list for the picker.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_fundraiser_overview()
RETURNS TABLE (
  campaign_key    TEXT,
  title           TEXT,
  status          TEXT,
  goal_cents      INTEGER,
  raised_cents    BIGINT,
  pending_cents   BIGINT,
  pending_count   INTEGER,
  supporters      INTEGER,
  currency        TEXT,
  amounts_cents   TEXT,
  created_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_key TEXT;
BEGIN
  PERFORM public.assert_staff('viewer');

  SELECT COALESCE(value, 'ios_launch_2026') INTO v_key
    FROM public.app_config WHERE key = 'fundraiser_campaign_key';

  RETURN QUERY
    SELECT
      c.key,
      c.title,
      -- Report the EFFECTIVE status, matching what members see, rather
      -- than the stored one: a campaign past its goal reads 'completed'
      -- on the card, and the console must not disagree with the card.
      CASE WHEN c.status = 'active'
                 AND COALESCE(r.raised, 0) >= c.goal_cents
           THEN 'completed' ELSE c.status END,
      c.goal_cents,
      COALESCE(r.raised, 0)::BIGINT,
      COALESCE(p.pending, 0)::BIGINT,
      COALESCE(p.pending_n, 0)::INTEGER,
      COALESCE(r.supporters, 0)::INTEGER,
      c.currency,
      c.amounts_cents,
      c.created_at,
      c.completed_at
    FROM public.fundraiser_campaigns c
    LEFT JOIN LATERAL (
      SELECT SUM(x.amount_cents) AS raised,
             COUNT(DISTINCT x.user_id) AS supporters
        FROM public.fundraiser_contributions x
       WHERE x.campaign_key = c.key AND x.status = 'confirmed'
    ) r ON TRUE
    LEFT JOIN LATERAL (
      SELECT SUM(x.amount_cents) AS pending, COUNT(*) AS pending_n
        FROM public.fundraiser_contributions x
       WHERE x.campaign_key = c.key AND x.status = 'pending'
    ) p ON TRUE
    -- Live campaign first, then newest.
    ORDER BY (c.key = v_key) DESC, c.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_fundraiser_overview() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_fundraiser_overview() TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 5 — Stopping a campaign
--
--  The button the founder actually asked for. 'completed' switches the
--  card to its thank-you; 'paused' removes the card altogether.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_fundraiser_status(
  p_key    TEXT,
  p_status TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_before TEXT;
BEGIN
  PERFORM public.assert_staff('owner');

  IF p_status NOT IN ('active', 'paused', 'completed') THEN
    RAISE EXCEPTION 'Unknown campaign status.' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_before
    FROM public.fundraiser_campaigns WHERE key = p_key;
  IF v_before IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE public.fundraiser_campaigns
     SET status       = p_status,
         completed_at = CASE WHEN p_status = 'completed'
                             THEN COALESCE(completed_at, NOW())
                             ELSE NULL END
   WHERE key = p_key;

  -- app_config is what patch_253's fallback path and any older build
  -- reads. Keep the two in step for the LIVE campaign only.
  IF p_key = (SELECT value FROM public.app_config
               WHERE key = 'fundraiser_campaign_key') THEN
    INSERT INTO public.app_config (key, value)
      VALUES ('fundraiser_status', p_status)
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  END IF;

  PERFORM public.log_admin_action(
    'fundraiser_set_status', 'fundraiser_campaign', p_key,
    jsonb_build_object('status', v_before),
    jsonb_build_object('status', p_status));

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_fundraiser_status(TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_fundraiser_status(TEXT, TEXT)
  TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 6 — Starting the next campaign
--
--  Creates the row and, optionally, points the app at it. Two steps in
--  one call because the alternative — create, then remember to
--  activate — leaves a half-made campaign lying around.
--
--  NOTE the deliberate absence: nothing anywhere calls this on
--  completion. A new campaign is always a decision someone made.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_create_fundraiser_campaign(
  p_key           TEXT,
  p_title         TEXT,
  p_body          TEXT,
  p_goal_cents    INTEGER,
  p_currency      TEXT DEFAULT 'USD',
  p_amounts_cents TEXT DEFAULT '100,300,500,1000',
  p_thanks_title  TEXT DEFAULT 'We did it',
  p_thanks_body   TEXT DEFAULT
    'Thank you to everyone who helped. You made it happen.',
  p_activate      BOOLEAN DEFAULT FALSE
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_key TEXT := LOWER(TRIM(COALESCE(p_key, '')));
BEGIN
  PERFORM public.assert_staff('owner');

  -- The key is a database identifier that ends up in every contribution
  -- and dismissal row, so it is normalised rather than trusted.
  v_key := regexp_replace(v_key, '[^a-z0-9_]+', '_', 'g');
  v_key := regexp_replace(v_key, '^_+|_+$', '', 'g');
  IF v_key = '' OR length(v_key) > 64 THEN
    RAISE EXCEPTION 'Give the campaign a short name (letters and numbers).'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (SELECT 1 FROM public.fundraiser_campaigns WHERE key = v_key) THEN
    RAISE EXCEPTION 'A campaign called "%" already exists.', v_key
      USING ERRCODE = '23505';
  END IF;

  IF COALESCE(p_goal_cents, 0) <= 0 OR p_goal_cents > 100000000 THEN
    RAISE EXCEPTION 'Set a goal above zero.' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(TRIM(p_title), '') = '' OR COALESCE(TRIM(p_body), '') = '' THEN
    RAISE EXCEPTION 'A campaign needs a heading and a sentence explaining it.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.fundraiser_campaigns
    (key, title, body, goal_cents, currency, amounts_cents, status,
     thanks_title, thanks_body, created_by)
  VALUES
    (v_key, LEFT(TRIM(p_title), 80), LEFT(TRIM(p_body), 400), p_goal_cents,
     COALESCE(NULLIF(TRIM(p_currency), ''), 'USD'),
     COALESCE(NULLIF(TRIM(p_amounts_cents), ''), '100,300,500,1000'),
     'active',
     LEFT(COALESCE(NULLIF(TRIM(p_thanks_title), ''), 'We did it'), 80),
     LEFT(COALESCE(NULLIF(TRIM(p_thanks_body), ''),
          'Thank you to everyone who helped. You made it happen.'), 400),
     auth.uid());

  IF p_activate THEN
    PERFORM public.admin_activate_fundraiser_campaign(v_key);
  END IF;

  PERFORM public.log_admin_action(
    'fundraiser_create_campaign', 'fundraiser_campaign', v_key,
    NULL,
    jsonb_build_object('title', p_title, 'goal_cents', p_goal_cents,
                       'activated', COALESCE(p_activate, FALSE)));

  RETURN v_key;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_fundraiser_campaign(
  TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_create_fundraiser_campaign(
  TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_activate_fundraiser_campaign(
  p_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_before TEXT;
  v_c      public.fundraiser_campaigns%ROWTYPE;
BEGIN
  PERFORM public.assert_staff('owner');

  SELECT * INTO v_c FROM public.fundraiser_campaigns WHERE key = p_key;
  IF v_c.key IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT value INTO v_before FROM public.app_config
   WHERE key = 'fundraiser_campaign_key';

  -- Point the app at it, and mirror its settings into the app_config
  -- keys patch_253's fallback path still reads.
  INSERT INTO public.app_config (key, value) VALUES
    ('fundraiser_campaign_key',  v_c.key),
    ('fundraiser_status',        v_c.status),
    ('fundraiser_goal_cents',    v_c.goal_cents::TEXT),
    ('fundraiser_currency',      v_c.currency),
    ('fundraiser_amounts_cents', v_c.amounts_cents)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  PERFORM public.log_admin_action(
    'fundraiser_activate_campaign', 'fundraiser_campaign', p_key,
    jsonb_build_object('campaign_key', v_before),
    jsonb_build_object('campaign_key', p_key));

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_activate_fundraiser_campaign(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_fundraiser_campaign(TEXT)
  TO authenticated;


-- ---------------------------------------------------------------------
--  SECTION 7 — Close patch_253's anon gap
--
--  New functions get EXECUTE via PUBLIC, which every role inherits —
--  so `REVOKE ... FROM anon` alone is a silent no-op, as patch_254
--  documents at length after making exactly that mistake. Revoke
--  PUBLIC.
--
--  This section is not optional here: Section 3 DROPs and recreates
--  fundraiser_status(), and Sections 4-6 create four new functions.
--  All five arrive with PUBLIC holding EXECUTE.
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND (p.proname LIKE 'fundraiser%'
            OR p.proname LIKE 'admin_fundraiser%'
            OR p.proname LIKE 'admin_set_fundraiser%'
            OR p.proname LIKE 'admin_create_fundraiser%'
            OR p.proname LIKE 'admin_activate_fundraiser%')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
  END LOOP;
END $$;

-- The full intended grant list, re-stated in one place. The revoke loop
-- above only named PUBLIC and anon, so these all survive it — but after
-- a DROP + CREATE it is worth having the whole list somewhere explicit
-- rather than trusting that every section remembered its own GRANT.
--
-- Member calls:
GRANT EXECUTE ON FUNCTION public.fundraiser_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_dismiss() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_record_pledge(INTEGER, TEXT, TEXT)
  TO authenticated;

-- Founder calls from the in-app admin queue, gated by is_super_admin():
GRANT EXECUTE ON FUNCTION public.fundraiser_list_pending() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_confirm_contribution(BIGINT, INTEGER)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_reject_contribution(BIGINT, TEXT)
  TO authenticated;

-- Web console calls, gated by assert_staff():
GRANT EXECUTE ON FUNCTION public.admin_fundraiser_overview() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_fundraiser_status(TEXT, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_activate_fundraiser_campaign(TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_fundraiser_campaign(
  TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;


-- =====================================================================
--  VERIFICATION
-- =====================================================================
-- 1. The live campaign survived the move, copy and all:
--      SELECT campaign_key, status, goal_cents, title, body
--        FROM public.fundraiser_status();
--      -- body should read "... raising $99 for the Apple Developer fee ..."
--      --                                ^ substituted from goal_cents
--
-- 2. Stopping it shows the thank-you and stops asking:
--      SELECT public.admin_set_fundraiser_status('ios_launch_2026','completed');
--      SELECT status FROM public.fundraiser_status();   -- completed
--      SELECT public.fundraiser_record_pledge(100);     -- NULL, not accepting
--
-- 3. Pausing removes the card entirely:
--      SELECT public.admin_set_fundraiser_status('ios_launch_2026','paused');
--      SELECT status FROM public.fundraiser_status();   -- paused
--      -- the Flutter card renders SizedBox.shrink on 'paused'
--
-- 4. A second campaign does not inherit the first one's money:
--      SELECT public.admin_create_fundraiser_campaign(
--        'server_2027','Keep the app running',
--        'We are raising {goal} for next year''s hosting.',
--        5000,'USD','100,300,500,1000','Thank you',
--        'You keep this running.', TRUE);
--      SELECT campaign_key, goal_cents, raised_cents FROM public.fundraiser_status();
--      -- server_2027 | 5000 | 0     <- iPhone money did not carry over
--
-- 5. The anti-nag cooldown holds:
--      -- as a member who dismissed the iPhone card today:
--      SELECT dismissed FROM public.fundraiser_status();
--      -- t, even though server_2027 was never dismissed
--
-- 6. patch_253's security properties are unchanged:
--      SELECT policyname, cmd FROM pg_policies
--       WHERE tablename = 'fundraiser_contributions';
--      -- exactly two rows: INSERT and SELECT. No UPDATE. No DELETE.
--      SELECT has_function_privilege('anon',
--        'public.admin_set_fundraiser_status(text,text)', 'EXECUTE');
--      -- f
-- =====================================================================
