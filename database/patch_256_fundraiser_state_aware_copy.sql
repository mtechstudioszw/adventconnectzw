-- =====================================================================
--  PATCH 256 — return the copy that matches the campaign's STATE
--
--  patch_255 moved the card's wording into `fundraiser_campaigns` and
--  gave every campaign two pairs of text:
--
--    title        / body         — while it is asking
--    thanks_title / thanks_body  — once it is funded
--
--  ...and then `fundraiser_status()` only ever returned the first pair.
--  The thank-you a campaign was created with was unreachable, so the
--  Flutter card kept its hardcoded "We did it" / "...closer to iPhone",
--  which is correct for THIS campaign and wrong for every future one.
--
--  ## The fix, and why it is shaped this way
--
--  `fundraiser_status()` now returns whichever pair matches the effective
--  status. The client renders `title` and `body` and never learns that
--  two pairs exist.
--
--  The alternative — return all four columns and let the app choose —
--  was rejected. It puts a branch in the UI that has to stay in step with
--  the server's definition of "completed", and that definition is not
--  trivial: a campaign is completed when the founder says so OR when
--  raised >= goal, and only the server knows the second one. Two places
--  computing that is one place too many.
--
--  Return type is unchanged, so this is a plain CREATE OR REPLACE — no
--  DROP, and therefore no ACL reset to clean up after (see patch_254 for
--  why that matters).
--
--  IDEMPOTENT: yes.
-- =====================================================================

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
  v_thx_title  TEXT;
  v_thx_body   TEXT;
  v_raised     BIGINT;
  v_supporters INTEGER;
  v_dismissed  BOOLEAN;
  v_pending    INTEGER;
  v_cooldown   INTEGER;
  v_last_dismiss TIMESTAMPTZ;
  v_goal_label TEXT;
BEGIN
  SELECT COALESCE(value, 'ios_launch_2026') INTO v_key
    FROM public.app_config WHERE key = 'fundraiser_campaign_key';
  v_key := COALESCE(v_key, 'ios_launch_2026');

  SELECT * INTO v_c FROM public.fundraiser_campaigns WHERE key = v_key;

  IF v_c.key IS NOT NULL THEN
    v_status    := v_c.status;
    v_goal      := v_c.goal_cents;
    v_currency  := v_c.currency;
    v_amounts   := v_c.amounts_cents;
    v_title     := v_c.title;
    v_body      := v_c.body;
    v_thx_title := v_c.thanks_title;
    v_thx_body  := v_c.thanks_body;
  ELSE
    SELECT COALESCE(value, 'active') INTO v_status
      FROM public.app_config WHERE key = 'fundraiser_status';
    SELECT COALESCE(NULLIF(regexp_replace(value, '\D', '', 'g'), '')::INTEGER, 9900)
      INTO v_goal FROM public.app_config WHERE key = 'fundraiser_goal_cents';
    SELECT COALESCE(value, 'USD') INTO v_currency
      FROM public.app_config WHERE key = 'fundraiser_currency';
    SELECT COALESCE(value, '100,300,500,1000') INTO v_amounts
      FROM public.app_config WHERE key = 'fundraiser_amounts_cents';
    v_title     := 'Help us reach iPhone';
    v_body      := 'Adventist Super App is on Android today. We are raising '
                   || '{goal} for the Apple Developer fee so we can publish '
                   || 'it for iPhone users too.';
    v_thx_title := 'We did it';
    v_thx_body  := 'Thank you to everyone who helped bring Adventist Super '
                   || 'App closer to iPhone. You made the publishing fee.';
  END IF;

  v_status := COALESCE(v_status, 'active');
  IF v_status NOT IN ('active', 'paused', 'completed') THEN
    v_status := 'active';
  END IF;
  v_goal     := GREATEST(COALESCE(v_goal, 9900), 1);
  v_currency := COALESCE(v_currency, 'USD');
  v_amounts  := COALESCE(NULLIF(TRIM(v_amounts), ''), '100,300,500,1000');

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

  IF v_status = 'active' AND v_raised >= v_goal THEN
    v_status := 'completed';
  END IF;

  -- The goal as a member would write it, for {goal} substitution.
  v_goal_label := CASE
    WHEN v_currency = 'USD' THEN '$'
    WHEN v_currency = 'ZAR' THEN 'R'
    WHEN v_currency = 'GBP' THEN '£'
    WHEN v_currency = 'EUR' THEN '€'
    ELSE v_currency || ' '
  END || CASE WHEN v_goal % 100 = 0
              THEN (v_goal / 100)::TEXT
              ELSE to_char(v_goal / 100.0, 'FM999999990.00') END;

  -- THE CHANGE: a funded campaign hands back its thank-you as the title
  -- and body. The client renders one pair and branches on nothing.
  IF v_status = 'completed' THEN
    v_title := COALESCE(NULLIF(TRIM(v_thx_title), ''), 'We did it');
    v_body  := COALESCE(NULLIF(TRIM(v_thx_body), ''),
                        'Thank you to everyone who helped.');
  END IF;

  RETURN QUERY SELECT
    v_key, v_status, v_goal, v_raised,
    GREATEST(v_goal::BIGINT - v_raised, 0),
    v_currency, v_amounts,
    COALESCE(v_supporters, 0),
    COALESCE(v_dismissed, FALSE),
    COALESCE(v_pending, 0),
    v_title,
    -- Substituted in both pairs: a thank-you may reasonably want to name
    -- the amount that was raised, and {goal} should not survive into the UI
    -- under any state.
    REPLACE(v_body, '{goal}', v_goal_label);
END;
$$;

-- Return type unchanged, so no DROP happened and the ACL is intact.
-- Re-stated anyway, because a grant list that is only correct by
-- accident is one refactor from being wrong.
REVOKE ALL ON FUNCTION public.fundraiser_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fundraiser_status() TO authenticated;


-- =====================================================================
--  VERIFICATION
-- =====================================================================
-- 1. While active, the asking copy:
--      SELECT status, title, body FROM public.fundraiser_status();
--      -- active | Help us reach iPhone | ...raising $99 for the Apple...
--
-- 2. Once completed, the SAME two columns carry the thank-you:
--      SELECT public.admin_set_fundraiser_status('ios_launch_2026','completed');
--      SELECT status, title, body FROM public.fundraiser_status();
--      -- completed | We did it | Thank you to everyone who helped bring...
--      SELECT public.admin_set_fundraiser_status('ios_launch_2026','active');
--
-- 3. No {goal} placeholder ever escapes to the client:
--      SELECT count(*) FROM public.fundraiser_status()
--       WHERE body LIKE '%{goal}%';    -- 0
--
-- 4. Still locked down:
--      SELECT has_function_privilege('anon','public.fundraiser_status()','EXECUTE');
--      -- f
-- =====================================================================
