-- =====================================================================
--  PATCH 005 — Message requests
--
--  WHY:  A first message from someone you've never chatted with should
--        land in a separate "Requests" inbox until you accept, so the
--        main chat list stays free of cold pitches and spam. Mirrors
--        the WhatsApp / IG model called for in the master reference
--        Stage 16 ("Message requests").
--
--  SHAPE:
--   - request_status text — 'pending' | 'accepted' | 'declined'
--                            default 'pending' for NEW rows; existing
--                            rows are backfilled to 'accepted' so we
--                            don't bury active chats behind a request
--                            wall after the migration.
--   - initiator_id   uuid → profiles(id). Filled in by the client when
--                            the conversation is created. Used by the
--                            UI to decide which side sees the convo as
--                            "pending request from a stranger".
--
--  ACCESS:
--   - Reads stay open to both participants regardless of request_status
--     so the recipient can preview the request body before deciding.
--   - Status changes go through the existing
--     conversations_update_participant policy (still gated by
--     user_is_active()).
--   - Declines are implemented as DELETE on the conversations row (RLS
--     allows participants to delete via the messaging service).
--
--  PREREQUISITES: schema.sql, patch_001..patch_004 all applied.
--                 Specifically depends on the scalar participant
--                 columns added in patch_003.
--  IDEMPOTENT:    yes — IF NOT EXISTS / IF EXISTS throughout.
-- =====================================================================


-- ----- 1. Columns ----------------------------------------------------
-- Add with default 'accepted' first so existing rows get backfilled to
-- 'accepted' (active chats stay where they are), then flip the column
-- default to 'pending' so future inserts land as requests.
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS request_status text NOT NULL DEFAULT 'accepted'
    CHECK (request_status IN ('pending', 'accepted', 'declined')),
  ADD COLUMN IF NOT EXISTS initiator_id uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.conversations
  ALTER COLUMN request_status SET DEFAULT 'pending';


-- ----- 2. Allow participants to DELETE their own conversation -------
-- Declining a request is implemented client-side as DELETE so the row
-- and its messages cascade away. schema.sql never set a DELETE policy
-- so participants currently can't delete; add one here (still gated by
-- user_is_active to honour the global ban check).
DROP POLICY IF EXISTS "conversations_delete_participant" ON public.conversations;
CREATE POLICY "conversations_delete_participant" ON public.conversations
  FOR DELETE USING (
    (auth.uid() = participant_a_id OR auth.uid() = participant_b_id)
    AND public.user_is_active()
  );


-- ----- 3. Indexes ----------------------------------------------------
-- Pending-requests-for-me query: "where I'm a participant, I'm NOT the
-- initiator, and status = pending". The participant-side indexes from
-- patch_003 already cover the most-recent-first ordering; this one
-- speeds up the status filter.
CREATE INDEX IF NOT EXISTS idx_conversations_request_status
  ON public.conversations (request_status, last_message_at DESC NULLS LAST);
