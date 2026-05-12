-- =====================================================================
--  PATCH 003 — Conversations: migrate to V4 scalar columns
--
--  WHY:  schema.sql models a conversation as `participant_ids UUID[]`,
--        but the Flutter client and every later feature (voice notes,
--        message requests, seller chat, etc.) read/write the V4 layout
--        with two scalar uuid columns + denormalised names + an explicit
--        last_sender_id. Without this migration, every conversations
--        SELECT from the app returns zero rows, INSERTs fail RLS, and
--        patch_004 (voice notes) can't even install because its policies
--        reference participant_a_id / participant_b_id.
--
--  WHAT THIS PATCH DOES:
--   1. Adds five new columns on conversations:
--        participant_a_id   uuid → profiles
--        participant_b_id   uuid → profiles
--        participant_a_name text  (denormalised display name)
--        participant_b_name text  (denormalised display name)
--        last_sender_id     uuid → profiles
--   2. Backfills the new columns from `participant_ids` + `profiles`
--      and from `last_message_by`.
--   3. Drops every policy that references the legacy array column
--      (three on conversations + two on messages) so the array column
--      can actually be dropped.
--   4. Drops the legacy array column, its constraint, and its GIN index.
--   5. Re-creates all five policies against the new scalar columns,
--      gated by user_is_active() where the schema originals were.
--   6. Replaces patch_002's notify_new_message() trigger so it reads
--      the new columns.
--   7. Adds (participant_x_id, last_message_at DESC) indexes for the
--      common "my conversations, newest first" query.
--
--  PREREQUISITES:    schema.sql + patch_001 + patch_002 already run.
--  RUN BEFORE:       patch_004_voice_notes.sql (it depends on the new
--                    scalar columns existing in its storage RLS).
--  IDEMPOTENT:       yes — every step uses IF NOT EXISTS / DROP IF
--                    EXISTS, the backfills are guarded so they no-op
--                    once the legacy columns are gone, and re-creating
--                    NOT NULL on an already-NOT-NULL column is a no-op.
--                    Safe to re-run from any partial state.
-- =====================================================================


-- ----- 1. Add new V4 columns ----------------------------------------
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS participant_a_id   uuid
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS participant_b_id   uuid
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS participant_a_name text,
  ADD COLUMN IF NOT EXISTS participant_b_name text,
  ADD COLUMN IF NOT EXISTS last_sender_id     uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;


-- ----- 2. Backfill scalar IDs from the legacy array (if present) ----
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='conversations'
       AND column_name='participant_ids'
  ) THEN
    EXECUTE $sql$
      UPDATE public.conversations c
         SET participant_a_id = COALESCE(c.participant_a_id, c.participant_ids[1]),
             participant_b_id = COALESCE(c.participant_b_id, c.participant_ids[2])
       WHERE c.participant_ids IS NOT NULL
    $sql$;
  END IF;
END $$;


-- ----- 3. Backfill denormalised participant names from profiles -----
UPDATE public.conversations c
   SET participant_a_name = COALESCE(c.participant_a_name, pa.full_name),
       participant_b_name = COALESCE(c.participant_b_name, pb.full_name)
  FROM public.profiles pa, public.profiles pb
 WHERE pa.id = c.participant_a_id
   AND pb.id = c.participant_b_id
   AND (c.participant_a_name IS NULL OR c.participant_b_name IS NULL);


-- ----- 4. Backfill last_sender_id from legacy last_message_by -------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='conversations'
       AND column_name='last_message_by'
  ) THEN
    EXECUTE
      'UPDATE public.conversations
          SET last_sender_id = COALESCE(last_sender_id, last_message_by)';
  END IF;
END $$;


-- ----- 5. Drop every policy that references the legacy array --------
-- Postgres tracks column dependencies for policies (not for function
-- bodies), so the column drop in step 6 will fail unless these are
-- gone first. We re-create them in step 7 against the scalar columns.
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_participant" ON public.conversations;
DROP POLICY IF EXISTS "messages_select_participant"      ON public.messages;
DROP POLICY IF EXISTS "messages_insert_sender"           ON public.messages;


-- ----- 6. Drop legacy array column, its constraint and its index ----
DROP INDEX IF EXISTS public.idx_conversations_participants;
ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_participants_chk;
ALTER TABLE public.conversations DROP COLUMN IF EXISTS participant_ids;
ALTER TABLE public.conversations DROP COLUMN IF EXISTS last_message_by;


-- ----- 7. Re-create RLS against the new scalar columns --------------
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    auth.uid() = participant_a_id OR auth.uid() = participant_b_id
  );

CREATE POLICY "conversations_insert_participant" ON public.conversations
  FOR INSERT WITH CHECK (
    (auth.uid() = participant_a_id OR auth.uid() = participant_b_id)
    AND public.user_is_active()
  );

CREATE POLICY "conversations_update_participant" ON public.conversations
  FOR UPDATE USING (
    (auth.uid() = participant_a_id OR auth.uid() = participant_b_id)
    AND public.user_is_active()
  ) WITH CHECK (
    (auth.uid() = participant_a_id OR auth.uid() = participant_b_id)
    AND public.user_is_active()
  );

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND (auth.uid() = c.participant_a_id
             OR auth.uid() = c.participant_b_id)
    )
  );

CREATE POLICY "messages_insert_sender" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND public.user_is_active()
    AND EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND (auth.uid() = c.participant_a_id
             OR auth.uid() = c.participant_b_id)
    )
  );


-- ----- 8. Lock down the new ID columns ------------------------------
-- Safe: any row that survived backfill has both IDs populated.
-- ALTER ... SET NOT NULL is a no-op if the column already is NOT NULL.
ALTER TABLE public.conversations
  ALTER COLUMN participant_a_id SET NOT NULL,
  ALTER COLUMN participant_b_id SET NOT NULL;


-- ----- 9. Indexes ----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_conversations_participant_a
  ON public.conversations (participant_a_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_conversations_participant_b
  ON public.conversations (participant_b_id, last_message_at DESC NULLS LAST);


-- ----- 10. Replace patch_002's new-message notification trigger -----
-- The old version reads participant_ids; rewrite it to read the new
-- scalar columns so notifications keep firing after this migration.
CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  a     uuid;
  b     uuid;
  other uuid;
BEGIN
  SELECT participant_a_id, participant_b_id
    INTO a, b
    FROM public.conversations
   WHERE id = NEW.conversation_id;

  IF a IS NULL OR b IS NULL THEN RETURN NEW; END IF;

  other := CASE WHEN NEW.sender_id = a THEN b ELSE a END;
  IF other IS NULL OR other = NEW.sender_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    other,
    'New message',
    COALESCE(substr(NEW.content, 1, 140), 'You have a new message.'),
    'message',
    NEW.conversation_id::text,
    'conversation'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
