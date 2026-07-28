-- =====================================================================
--  PATCH 167 — Answered prayers: when, and what happened
--
--  `prayers.is_answered` has existed since the base schema (schema.sql
--  line 184) and patch_006 already fires `notify_prayer_answered` on its
--  FALSE → TRUE transition. What was never stored is the two things that
--  make an answered prayer worth reading:
--
--    answered_at — WHEN it was answered. Without it the feed can only
--                  sort answered prayers by when they were REQUESTED,
--                  so a request from March that was answered yesterday
--                  sorts below one answered in April. The whole point of
--                  an "Answered" filter is recency of the answer.
--
--    testimony   — WHAT happened. "She's out of theatre and recovering
--                  well" is the content people screenshot and share. A
--                  boolean alone turns the feed into a list of things
--                  that silently stopped being urgent.
--
--  Additive only: two nullable columns and one partial index. No RLS
--  change — the existing prayers policies already gate UPDATE to the
--  author (`author_id = auth.uid()`), which is exactly who may mark a
--  prayer answered and write its testimony.
-- =====================================================================

ALTER TABLE public.prayers
  ADD COLUMN IF NOT EXISTS answered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS testimony   TEXT;

COMMENT ON COLUMN public.prayers.answered_at IS
  'Set when is_answered flips to TRUE. Drives ordering of the Answered '
  'filter — answered prayers sort by when they were ANSWERED, not posted.';

COMMENT ON COLUMN public.prayers.testimony IS
  'Optional short account of how the prayer was answered, written by the '
  'author. Rendered on the answered card in place of a second request.';

-- Keep the two columns honest with the boolean that already exists:
-- answered_at is present exactly when is_answered is true. Written as a
-- NOT VALID constraint so the patch cannot fail on historical rows that
-- were marked answered before this column existed; the backfill below
-- fixes those, then we validate.
ALTER TABLE public.prayers
  DROP CONSTRAINT IF EXISTS prayers_answered_at_matches_flag;

-- Backfill: any row already flagged answered gets its answered_at
-- seeded from updated_at (the closest honest approximation we have)
-- so the Answered filter has something to sort by on day one.
UPDATE public.prayers
   SET answered_at = COALESCE(updated_at, created_at)
 WHERE is_answered = TRUE
   AND answered_at IS NULL;

ALTER TABLE public.prayers
  ADD CONSTRAINT prayers_answered_at_matches_flag
  CHECK (
    (is_answered = TRUE  AND answered_at IS NOT NULL) OR
    (is_answered = FALSE AND answered_at IS NULL)
  ) NOT VALID;

ALTER TABLE public.prayers VALIDATE CONSTRAINT prayers_answered_at_matches_flag;

-- Stamp answered_at automatically on the flag transition, so a client
-- that only flips is_answered can never violate the CHECK above, and
-- un-answering clears it. Mirrors how patch_006's notify trigger reads
-- the same transition.
CREATE OR REPLACE FUNCTION public.stamp_prayer_answered_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_answered = TRUE AND COALESCE(OLD.is_answered, FALSE) = FALSE THEN
    NEW.answered_at := COALESCE(NEW.answered_at, now());
  ELSIF NEW.is_answered = FALSE THEN
    NEW.answered_at := NULL;
    NEW.testimony   := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_prayer_answered_at ON public.prayers;
CREATE TRIGGER trg_stamp_prayer_answered_at
  BEFORE UPDATE OF is_answered ON public.prayers
  FOR EACH ROW
  EXECUTE FUNCTION public.stamp_prayer_answered_at();

-- Partial index: the Answered filter reads only answered rows and always
-- orders by answered_at DESC. Partial keeps it small — answered prayers
-- are a minority of the table.
CREATE INDEX IF NOT EXISTS idx_prayers_answered_at
  ON public.prayers (answered_at DESC)
  WHERE is_answered = TRUE;
