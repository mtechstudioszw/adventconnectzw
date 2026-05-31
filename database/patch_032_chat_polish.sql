-- =====================================================================
--  PATCH 032 — Chat polish: receipts RLS gap, soft-delete, privacy flags
--
--  WHY:
--   1. RLS on `messages` only permits the SENDER to UPDATE the row
--      (`messages_update_sender` in schema.sql). The recipient's
--      attempt to flip `delivered_at` / `read` therefore matches
--      zero rows server-side — UPDATE returns success with no
--      effect. Result: chat ticks stayed at single ✓ even after the
--      message reached the device, and the unread badge wouldn't
--      actually clear on the server (it only looked like it did
--      because we cached client-side). Patch_018 added the column
--      but never opened the policy.
--
--   2. Deleting a conversation was implemented as a hard DELETE on
--      the conversations row (RLS permits any participant). The
--      other party's copy of the thread disappears too, which is
--      not the WhatsApp behaviour the user expects.
--
--   3. The chat-privacy screen reads + writes three boolean columns
--      on profiles — `show_last_seen`, `show_online_status`,
--      `show_read_receipts` — that no migration ever created. The
--      screen looked like it worked but no value ever persisted.
--
--  WHAT THIS PATCH DOES:
--   1. SECURITY DEFINER RPCs `mark_message_delivered(uuid[])` and
--      `mark_conversation_read(bigint, boolean)` perform the
--      column-scoped UPDATEs the recipient needs without opening
--      the row up to arbitrary edits. The Flutter service calls
--      these instead of the previous direct UPDATEs.
--   2. `conversations.deleted_by_a_at` + `deleted_by_b_at`
--      timestamps. The fetchConversations query filters out rows
--      where the requester's side is set AND no newer message has
--      arrived since the soft-delete (so a new inbound message
--      "undeletes" the thread, matching WhatsApp). The thread is
--      hard-deleted automatically once both sides have soft-deleted.
--   3. `profiles.show_last_seen`, `show_online_status`,
--      `show_read_receipts` BOOLEAN NOT NULL DEFAULT TRUE so the
--      privacy screen's writes actually land.
--
--  IDEMPOTENT: yes — IF NOT EXISTS / CREATE OR REPLACE throughout.
-- =====================================================================


-- ----- 1. Privacy flags on profiles ---------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_last_seen     BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS show_online_status BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS show_read_receipts BOOLEAN NOT NULL DEFAULT TRUE;


-- ----- 2. Per-side soft-delete on conversations ---------------------
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS deleted_by_a_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by_b_at TIMESTAMPTZ;


-- ----- 3. Recipient-side receipt RPCs -------------------------------
-- Mark a batch of incoming messages as delivered (recipient's device
-- now has them). Idempotent: if delivered_at is already set we leave
-- it alone so the original delivery time is preserved.
CREATE OR REPLACE FUNCTION public.mark_message_delivered(p_ids UUID[])
RETURNS VOID AS $$
DECLARE
  v_user UUID := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to mark messages delivered.';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN;
  END IF;
  UPDATE public.messages m
     SET delivered_at = COALESCE(m.delivered_at, NOW())
    FROM public.conversations c
   WHERE m.id = ANY(p_ids)
     AND m.conversation_id = c.id
     AND m.sender_id <> v_user
     AND (c.participant_a_id = v_user OR c.participant_b_id = v_user);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.mark_message_delivered(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_message_delivered(UUID[]) TO authenticated;


-- Mark every unread incoming message in a conversation as read. When
-- `p_with_timestamp` is FALSE we still flip `read` (so the badge
-- clears) but leave read_at NULL (so the sender never sees the blue
-- tick) — used when the viewer has turned read receipts off.
CREATE OR REPLACE FUNCTION public.mark_conversation_read(
  p_conversation_id BIGINT,
  p_with_timestamp  BOOLEAN DEFAULT TRUE
)
RETURNS VOID AS $$
DECLARE
  v_user UUID := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to mark messages read.';
  END IF;
  UPDATE public.messages m
     SET "read"  = TRUE,
         read_at = CASE
                     WHEN p_with_timestamp AND m.read_at IS NULL
                       THEN NOW()
                     ELSE m.read_at
                   END,
         -- Also set delivered_at if we somehow read before a delivery
         -- ping arrived (e.g. cold-start straight into the chat).
         delivered_at = COALESCE(m.delivered_at, NOW())
    FROM public.conversations c
   WHERE m.conversation_id = p_conversation_id
     AND m.conversation_id = c.id
     AND m.sender_id <> v_user
     AND m."read" = FALSE
     AND (c.participant_a_id = v_user OR c.participant_b_id = v_user);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.mark_conversation_read(BIGINT, BOOLEAN)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(BIGINT, BOOLEAN)
  TO authenticated;


-- ----- 4. Soft-delete helper ----------------------------------------
-- Soft-deletes the conversation for the caller's side only. If the
-- other side has already soft-deleted, the row is hard-deleted (so
-- the messages cascade away and we don't accumulate orphaned threads
-- forever). Idempotent — re-deleting just refreshes the timestamp.
CREATE OR REPLACE FUNCTION public.soft_delete_conversation(
  p_conversation_id BIGINT
)
RETURNS VOID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_row  public.conversations;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to delete a conversation.';
  END IF;

  SELECT * INTO v_row
    FROM public.conversations
   WHERE id = p_conversation_id
     AND (participant_a_id = v_user OR participant_b_id = v_user);

  IF NOT FOUND THEN RETURN; END IF;

  IF v_user = v_row.participant_a_id THEN
    -- Other side already gone → hard delete.
    IF v_row.deleted_by_b_at IS NOT NULL
       OR v_row.participant_a_id = v_row.participant_b_id THEN
      DELETE FROM public.conversations WHERE id = p_conversation_id;
    ELSE
      UPDATE public.conversations
         SET deleted_by_a_at = NOW()
       WHERE id = p_conversation_id;
    END IF;
  ELSE
    IF v_row.deleted_by_a_at IS NOT NULL THEN
      DELETE FROM public.conversations WHERE id = p_conversation_id;
    ELSE
      UPDATE public.conversations
         SET deleted_by_b_at = NOW()
       WHERE id = p_conversation_id;
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.soft_delete_conversation(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_conversation(BIGINT)
  TO authenticated;


-- ----- 5. Auto-accept conversations between existing friends --------
-- WhatsApp doesn't have a "message request" wall between friends —
-- if A and B are already friends and A opens a DM with B, the
-- thread lands in B's main inbox, not Requests. This trigger sets
-- request_status='accepted' on insert when an accepted friendship
-- exists between the two participants. Self-chats and conversations
-- that already opt into 'accepted' (Notes-to-self, business contact)
-- are untouched.
CREATE OR REPLACE FUNCTION public.conversations_auto_accept_friends()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.request_status = 'accepted' THEN RETURN NEW; END IF;
  IF NEW.participant_a_id = NEW.participant_b_id THEN RETURN NEW; END IF;

  IF EXISTS (
    SELECT 1
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (
         (f.requester_id = NEW.participant_a_id
            AND f.addressee_id = NEW.participant_b_id)
         OR
         (f.requester_id = NEW.participant_b_id
            AND f.addressee_id = NEW.participant_a_id)
       )
  ) THEN
    NEW.request_status := 'accepted';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_conversations_auto_accept_friends
  ON public.conversations;
CREATE TRIGGER trg_conversations_auto_accept_friends
  BEFORE INSERT ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.conversations_auto_accept_friends();


-- Existing pending conversations between people who are now friends
-- get promoted in one shot so the bug doesn't stick around for
-- pre-patch threads.
UPDATE public.conversations c
   SET request_status = 'accepted'
 WHERE request_status = 'pending'
   AND EXISTS (
     SELECT 1
       FROM public.friendships f
      WHERE f.status = 'accepted'
        AND (
          (f.requester_id = c.participant_a_id
             AND f.addressee_id = c.participant_b_id)
          OR
          (f.requester_id = c.participant_b_id
             AND f.addressee_id = c.participant_a_id)
        )
   );


-- ----- 6. Update get_my_unread_counts to honour soft-delete ---------
-- The inbox unread RPC should ignore counts for threads the viewer
-- has soft-deleted (until a new message arrives that "undeletes"
-- the thread).
CREATE OR REPLACE FUNCTION public.get_my_unread_counts()
RETURNS TABLE (conversation_id BIGINT, unread_count INTEGER)
LANGUAGE SQL STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT m.conversation_id,
         COUNT(*)::INTEGER AS unread_count
    FROM public.messages m
    JOIN public.conversations c ON c.id = m.conversation_id
   WHERE m."read" = FALSE
     AND m.sender_id <> auth.uid()
     AND (c.participant_a_id = auth.uid()
       OR c.participant_b_id = auth.uid())
     AND NOT (
       c.participant_a_id = auth.uid()
       AND c.deleted_by_a_at IS NOT NULL
       AND m.created_at <= c.deleted_by_a_at
     )
     AND NOT (
       c.participant_b_id = auth.uid()
       AND c.deleted_by_b_at IS NOT NULL
       AND m.created_at <= c.deleted_by_b_at
     )
   GROUP BY m.conversation_id;
$$;
