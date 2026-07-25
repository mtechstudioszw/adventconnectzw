-- patch_163: Quiz Arena — coin balance + head-to-head challenges.

-- ---- Coins -----------------------------------------------------------------

ALTER TABLE public.quiz_progress
  ADD COLUMN IF NOT EXISTS coins integer NOT NULL DEFAULT 0
    CHECK (coins >= 0);

-- ---- Challenges ------------------------------------------------------------
--
-- The full question payload is stored on the row, not a list of ids. Half of
-- every round now comes from the KJV generator, and those questions have no
-- `quiz_questions` row to look up — storing ids would make it impossible to
-- guarantee both players answered the same questions, which is the entire
-- point of a head-to-head.

CREATE TABLE IF NOT EXISTS public.quiz_challenges (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenger_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  opponent_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  questions          jsonb NOT NULL,
  challenger_points  integer NOT NULL DEFAULT 0 CHECK (challenger_points >= 0),
  challenger_correct integer NOT NULL DEFAULT 0,
  opponent_points    integer CHECK (opponent_points IS NULL OR opponent_points >= 0),
  opponent_correct   integer,
  status             text NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','complete','declined','expired')),
  created_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz,
  expires_at         timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  CONSTRAINT quiz_challenges_not_self CHECK (challenger_id <> opponent_id)
);

CREATE INDEX IF NOT EXISTS quiz_challenges_opponent_idx
  ON public.quiz_challenges (opponent_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS quiz_challenges_challenger_idx
  ON public.quiz_challenges (challenger_id, created_at DESC);

ALTER TABLE public.quiz_challenges ENABLE ROW LEVEL SECURITY;

-- Either participant may read the row.
DROP POLICY IF EXISTS quiz_challenges_read ON public.quiz_challenges;
CREATE POLICY quiz_challenges_read ON public.quiz_challenges
  FOR SELECT TO authenticated
  USING (challenger_id = auth.uid() OR opponent_id = auth.uid());

-- Only the challenger creates, and only as themselves.
DROP POLICY IF EXISTS quiz_challenges_create ON public.quiz_challenges;
CREATE POLICY quiz_challenges_create ON public.quiz_challenges
  FOR INSERT TO authenticated
  WITH CHECK (challenger_id = auth.uid() AND opponent_id <> auth.uid());

-- NOTE: deliberately NO update policy. RLS can't restrict which *columns*
-- an update touches, so an opponent with UPDATE rights could rewrite the
-- challenger's score. Submitting a result goes through the RPC below.
GRANT SELECT, INSERT ON public.quiz_challenges TO authenticated;

-- ---- Submitting a result ---------------------------------------------------

CREATE OR REPLACE FUNCTION public.quiz_challenge_submit(
  p_challenge_id uuid,
  p_points integer,
  p_correct integer
)
RETURNS public.quiz_challenges
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.quiz_challenges;
BEGIN
  UPDATE public.quiz_challenges
     SET opponent_points  = GREATEST(COALESCE(p_points, 0), 0),
         opponent_correct = GREATEST(COALESCE(p_correct, 0), 0),
         status           = 'complete',
         completed_at     = now()
   WHERE id = p_challenge_id
     AND opponent_id = auth.uid()   -- only the challenged player
     AND status = 'pending'         -- and only once
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Challenge not found, already played, or not yours';
  END IF;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_challenge_submit(uuid, integer, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_challenge_submit(uuid, integer, integer)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.quiz_challenge_decline(p_challenge_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.quiz_challenges
     SET status = 'declined', completed_at = now()
   WHERE id = p_challenge_id
     AND opponent_id = auth.uid()
     AND status = 'pending';
$$;

REVOKE ALL ON FUNCTION public.quiz_challenge_decline(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_challenge_decline(uuid) TO authenticated;

-- ---- Notifications ---------------------------------------------------------
-- Follows the existing `notify_*` pattern: insert into public.notifications
-- and the notify-fcm webhook trigger on that table sends the push for free.

CREATE OR REPLACE FUNCTION public.notify_quiz_challenge()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text;
BEGIN
  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), 'Someone')
    INTO v_name
    FROM public.profiles p
   WHERE p.id = NEW.challenger_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    NEW.opponent_id,
    'Bible Quiz challenge',
    v_name || ' challenged you to a Bible Quiz. Can you beat '
      || NEW.challenger_points || ' points?',
    'quiz_challenge',
    NEW.id::text,
    'quiz_challenge'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quiz_challenges_notify_opponent ON public.quiz_challenges;
CREATE TRIGGER quiz_challenges_notify_opponent
  AFTER INSERT ON public.quiz_challenges
  FOR EACH ROW EXECUTE FUNCTION public.notify_quiz_challenge();

-- Tell the challenger how it went.
CREATE OR REPLACE FUNCTION public.notify_quiz_challenge_result()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text;
  v_body text;
BEGIN
  IF NEW.status <> 'complete' OR OLD.status = 'complete' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), 'Someone')
    INTO v_name
    FROM public.profiles p
   WHERE p.id = NEW.opponent_id;

  IF COALESCE(NEW.opponent_points, 0) > NEW.challenger_points THEN
    v_body := v_name || ' beat your score with '
              || NEW.opponent_points || ' points.';
  ELSIF COALESCE(NEW.opponent_points, 0) = NEW.challenger_points THEN
    v_body := 'You and ' || v_name || ' tied on '
              || NEW.challenger_points || ' points.';
  ELSE
    v_body := 'You beat ' || v_name || ' — they scored '
              || COALESCE(NEW.opponent_points, 0) || '.';
  END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    NEW.challenger_id,
    'Challenge result',
    v_body,
    'quiz_challenge',
    NEW.id::text,
    'quiz_challenge'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quiz_challenges_notify_result ON public.quiz_challenges;
CREATE TRIGGER quiz_challenges_notify_result
  AFTER UPDATE ON public.quiz_challenges
  FOR EACH ROW EXECUTE FUNCTION public.notify_quiz_challenge_result();

-- ---- Who can I challenge? --------------------------------------------------
-- Accepted friends only, so this can't become a channel for messaging
-- strangers. SECURITY DEFINER because `friendships` is read-restricted.

CREATE OR REPLACE FUNCTION public.quiz_challengeable_friends()
RETURNS TABLE (
  user_id     uuid,
  full_name   text,
  photo_url   text,
  is_verified boolean,
  pending     boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH friends AS (
    SELECT CASE WHEN f.requester_id = auth.uid()
                THEN f.addressee_id ELSE f.requester_id END AS other_id
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
  )
  SELECT p.id,
         COALESCE(NULLIF(btrim(p.full_name), ''), 'Member'),
         p.profile_photo_url,
         COALESCE(p.is_verified, false),
         EXISTS (
           SELECT 1 FROM public.quiz_challenges c
            WHERE c.status = 'pending'
              AND c.challenger_id = auth.uid()
              AND c.opponent_id = fr.other_id
         ) AS pending
    FROM friends fr
    JOIN public.profiles p ON p.id = fr.other_id
   WHERE COALESCE(p.is_banned, false) = false
   ORDER BY 2;
$$;

REVOKE ALL ON FUNCTION public.quiz_challengeable_friends() FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_challengeable_friends() TO authenticated;
