-- =====================================================================
--  PATCH 070 — message idempotency key (client_id)
--
--  Offline sends queue to the outbox and throw before sendMessage can
--  return the canonical row, so the optimistic bubble keeps its temp id.
--  When the outbox later flushes, the realtime echo arrives under a NEW
--  server id and the id-based dedupe can't match the optimistic row →
--  the message shows TWICE. A client-generated client_id stamped on both
--  the optimistic row and the insert lets the client dedupe reliably.
-- =====================================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS client_id TEXT;
