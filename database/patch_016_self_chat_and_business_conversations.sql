-- =====================================================================
--  PATCH 016 — Self-chat ("Notes to self") + business chat marker
--
--  WHY:
--   1. Users want a private "Notes to self" conversation so they can
--      jot reminders / drafts. There's no DB-level barrier today — the
--      conversations table never had a CHECK preventing
--      participant_a_id = participant_b_id. We still pin that down with
--      an explicit comment + add an index so the self-chat lookup is
--      O(log n) instead of a sequential scan, and make sure the new-
--      message notification trigger stays a no-op when the message is
--      to yourself (it already is — `other = NEW.sender_id` guard).
--
--   2. Conversations spawned from the marketplace need to be visibly
--      tagged "Business" in the inbox so the user knows that thread is
--      tied to a seller and not a friend. We do this by adding a
--      cheap boolean column rather than re-querying the marketplace
--      every time the inbox is rendered.
--
--  PREREQUISITES: schema.sql + patch_001..patch_015 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


-- ----- 1. Business flag on conversations ----------------------------
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS is_business BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.conversations.is_business IS
  'TRUE when the conversation was started from the marketplace / a '
  'business listing. The inbox renders a small "Business" badge on '
  'these rows so the user can tell sales chats from friend chats.';


-- ----- 2. Index for the self-chat lookup ----------------------------
-- A self-chat is just a row where the same uuid sits in both
-- participant columns. Without an index, MessagingService.openSelfChat
-- would do a sequential scan every time the user taps "Notes to self".
CREATE INDEX IF NOT EXISTS idx_conversations_self_chat
  ON public.conversations (participant_a_id)
  WHERE participant_a_id = participant_b_id;


COMMENT ON TABLE public.conversations IS
  'Direct chats between two profiles (V4 scalar layout — see patch_003). '
  'A self-chat ("Notes to self") is a row where '
  'participant_a_id = participant_b_id; the app pins it to the top of '
  'the inbox and the new-message trigger skips notifying yourself.';


-- =====================================================================
--  END OF PATCH 016
-- =====================================================================
