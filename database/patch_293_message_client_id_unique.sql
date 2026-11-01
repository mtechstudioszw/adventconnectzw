-- =====================================================================
--  PATCH 293 — a message sent twice by a retry is stored once
--  STATUS: APPLIED 1 Nov 2026 (by Claude via the Supabase connector)
--
--  1 Nov 2026, offline chat (owner: "when you send a message [offline] it
--  drafts that message, waiting for internet. Like WhatsApp").
--
--  The app now keeps a message in its outbox whenever the send fails for
--  ANY connection reason — including the case where the insert reached the
--  server but the reply was lost. Retrying that would post it twice. Every
--  message already carries a per-sender client_id; making it unique lets
--  the retry fail with 23505, which the app treats as "already sent".
--
--  Partial on purpose: two duplicates from before (lost-response retries)
--  already exist, and members' old messages are not touched. Only messages
--  from now on are held to it.
--
--  No profiles change, no triggers.
-- =====================================================================

CREATE UNIQUE INDEX IF NOT EXISTS messages_sender_client_id_uniq
  ON public.messages (sender_id, client_id)
  WHERE client_id IS NOT NULL
    AND created_at >= '2026-11-01 00:00:00+00';
