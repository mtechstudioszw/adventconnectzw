-- =====================================================================
--  PATCH 046 — One conversation per user pair (tester bug #14)
--
--  conversations had NO uniqueness on the participant pair, and the
--  app's get-or-create (reuse query + insert) isn't atomic — two quick
--  taps, or entering the same chat from two surfaces, could create
--  duplicate threads, "losing" the previous messages. There's already
--  1 duplicate pair in the data.
--
--  This patch:
--    1. Merges existing duplicates — moves messages onto the keeper
--       (most recent activity) and deletes the extra rows.
--    2. Adds a unique index on the unordered pair so the DB itself
--       guarantees one thread per pair. createConversation now catches
--       the 23505 conflict and re-fetches the keeper.
--
--  IDEMPOTENT: dedupe is a no-op once clean; index uses IF NOT EXISTS.
-- =====================================================================

-- ----- 1. Merge existing duplicate pairs ----------------------------
DO $$
DECLARE
  r RECORD;
  v_keep BIGINT;
BEGIN
  FOR r IN
    SELECT LEAST(participant_a_id, participant_b_id)    AS a,
           GREATEST(participant_a_id, participant_b_id) AS b
      FROM public.conversations
     GROUP BY 1, 2
    HAVING COUNT(*) > 1
  LOOP
    -- Keeper = the thread with the most recent activity.
    SELECT id INTO v_keep
      FROM public.conversations
     WHERE LEAST(participant_a_id, participant_b_id) = r.a
       AND GREATEST(participant_a_id, participant_b_id) = r.b
     ORDER BY last_message_at DESC NULLS LAST, id ASC
     LIMIT 1;

    -- Re-point messages from the duplicate threads onto the keeper.
    UPDATE public.messages m
       SET conversation_id = v_keep
      FROM public.conversations c
     WHERE m.conversation_id = c.id
       AND LEAST(c.participant_a_id, c.participant_b_id) = r.a
       AND GREATEST(c.participant_a_id, c.participant_b_id) = r.b
       AND c.id <> v_keep;

    -- Remove the now-empty duplicate threads.
    DELETE FROM public.conversations c
     WHERE LEAST(c.participant_a_id, c.participant_b_id) = r.a
       AND GREATEST(c.participant_a_id, c.participant_b_id) = r.b
       AND c.id <> v_keep;
  END LOOP;
END $$;

-- ----- 2. Unique index on the unordered participant pair ------------
CREATE UNIQUE INDEX IF NOT EXISTS conversations_unique_pair
  ON public.conversations (
    LEAST(participant_a_id, participant_b_id),
    GREATEST(participant_a_id, participant_b_id)
  );
