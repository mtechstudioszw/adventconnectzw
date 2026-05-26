-- =====================================================================
--  PATCH 018 — Chat receipts + per-category notification preferences
--
--  WHY:
--   1. The Flutter chat UI renders WhatsApp-style three-state ticks
--      (sent ✓ → delivered ✓✓ → read ✓✓ blue) but the messages table
--      had no `delivered_at` column, so every call to mark-as-delivered
--      hit a non-existent column and the second tick never appeared.
--   2. The Settings screen exposes per-category notification toggles
--      (events / prayers / messages / marketplace) but they were
--      ephemeral local state — flipping a toggle off neither persisted
--      across reopens nor stopped the Edge Function from pushing.
--      Users perceived them as "silently re-enabling" because the
--      toggle UI defaults reset every session.
--
--  WHAT THIS PATCH DOES:
--   1. ALTER messages ADD delivered_at timestamptz (nullable).
--   2. ALTER profiles ADD notif_categories jsonb (defaults to all-on).
--      Shape: { "events": bool, "prayers": bool, "messages": bool,
--               "marketplace": bool, "announcements": bool }.
--   3. Provides a helper get_my_unread_counts() RPC so the inbox can
--      ask "how many unread messages do I have in each conversation"
--      in a single round-trip — rather than scanning every message.
--
--  PREREQUISITES:    schema.sql + patches 001-017 already run.
--  IDEMPOTENT:       yes — every step uses IF NOT EXISTS / DROP IF
--                    EXISTS. Safe to re-run from any state.
-- =====================================================================


-- ----- 1. messages.delivered_at -------------------------------------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

-- Speeds up the "any-undelivered-for-this-conversation" check the
-- chat screen issues whenever a new realtime row arrives.
CREATE INDEX IF NOT EXISTS idx_messages_undelivered
  ON public.messages (conversation_id)
  WHERE delivered_at IS NULL;


-- ----- 2. profiles.notif_categories ---------------------------------
-- All categories default to TRUE — opt-out model, matches the
-- behaviour users expect when they first land on Settings.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_categories JSONB NOT NULL DEFAULT jsonb_build_object(
    'events',        TRUE,
    'prayers',       TRUE,
    'messages',      TRUE,
    'marketplace',   TRUE,
    'announcements', TRUE
  );


-- ----- 3. get_my_unread_counts() RPC --------------------------------
-- Returns one row per conversation the caller is a participant of,
-- with the count of unread messages they DID NOT send. RLS on
-- messages is already participant-scoped so a SECURITY INVOKER
-- function is fine (the caller can only count messages they're
-- allowed to read).
CREATE OR REPLACE FUNCTION public.get_my_unread_counts()
RETURNS TABLE (conversation_id BIGINT, unread_count INTEGER)
LANGUAGE SQL STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT m.conversation_id,
         COUNT(*)::INTEGER AS unread_count
    FROM public.messages m
    JOIN public.conversations c ON c.id = m.conversation_id
   WHERE m.read = FALSE
     AND m.sender_id <> auth.uid()
     AND (c.participant_a_id = auth.uid()
       OR c.participant_b_id = auth.uid())
   GROUP BY m.conversation_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_unread_counts() TO authenticated;
