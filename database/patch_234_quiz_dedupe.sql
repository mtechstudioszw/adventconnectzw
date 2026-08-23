-- =====================================================================
--  PATCH 234 — Remove reworded twin questions from the quiz bank
--
--  A second, independent cause of "the quiz repeats questions frequently".
--
--  patch fixed the ROTATION (pickFresh padded short pools with
--  already-seen rows). patch_233 fixed the POOL SIZE (seven categories
--  held fewer questions than a round). Neither touches this one: the bank
--  contains questions that are *worded differently but ask the same thing
--  and take the same answer*, so the seen-list treats them as two distinct
--  questions and happily serves both. To the member that is a repeat, and
--  the app is convinced it is not.
--
--  Examples, all real and all in the same category as their twin:
--
--    "In the parable of the ten virgins, how many were wise?"
--    "How many of the ten virgins were wise?"                    -> Five
--
--    "What is the number of the beast in Revelation?"
--    "What is the number of the beast in Revelation 13?"         -> 666
--
--    "What did Jesus call the death of Lazarus?"
--    "What did Jesus call Lazarus' death?"                       -> Sleep
--
--  ## Why matching on TEXT ALONE would have been destructive
--
--  Trigram similarity over the question text finds 59 pairs above 0.55.
--  Nineteen are duplicates. The rest are legitimately different questions
--  that merely read alike, and deleting them would have quietly removed
--  correct content:
--
--    "How many books are in the New Testament?"   -> 27
--    "How many books are in the Old Testament?"   -> 39      sim 0.81
--
--    "Most of the Old Testament was written in which language?"  -> Hebrew
--    "The New Testament was written in which language?"          -> Greek
--
--  The discriminator is the ANSWER. Two questions that read alike AND
--  resolve to the same correct option are the same question; two that read
--  alike and resolve differently are a matched pair someone wrote on
--  purpose. So the predicate below requires both.
--
--  Keeps the LOWEST id in each cluster, which is the earliest-authored
--  copy, and deletes the rest. Four of the nineteen are mine from
--  patch_233 — the same lesson as that patch's own dedupe note, one level
--  deeper: exact-match comparison is not enough either.
-- =====================================================================

-- What will go, for the record. Run this SELECT first if you want to
-- inspect before deleting; the DELETE below uses the identical predicate.
--
--   SELECT b.id, b.category, b.question, b.options->>b.correct_index AS answer
--     FROM public.quiz_questions b
--    WHERE EXISTS (
--            SELECT 1 FROM public.quiz_questions a
--             WHERE a.category = b.category
--               AND a.id < b.id
--               AND similarity(a.question, b.question) > 0.55
--               AND lower(btrim(a.options->>a.correct_index))
--                 = lower(btrim(b.options->>b.correct_index))
--          );

DELETE FROM public.quiz_questions b
 WHERE EXISTS (
   SELECT 1 FROM public.quiz_questions a
    WHERE a.category = b.category
      AND a.id < b.id
      AND similarity(a.question, b.question) > 0.55
      AND lower(btrim(a.options->>a.correct_index))
        = lower(btrim(b.options->>b.correct_index))
 );

-- ---------------------------------------------------------------------
--  Guard for the future. The bank is added to by hand and by batch, and
--  the twins above accumulated precisely because nothing checked. This
--  index makes the similarity lookup cheap enough to run before any
--  future insert:
--
--    SELECT question FROM quiz_questions
--     WHERE category = $1 AND similarity(question, $2) > 0.55;
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_quiz_questions_question_trgm
  ON public.quiz_questions USING gin (question gin_trgm_ops);
