-- =====================================================================
--  PATCH 063 — "This message was deleted" tombstone
--
--  "Delete for everyone" used to hard-delete the row (it just vanished).
--  Now it sets is_deleted=TRUE and the sender clears content/media via
--  the existing messages_update_sender policy, so both sides render a
--  WhatsApp-style "This message was deleted" placeholder. The sender can
--  still hard-delete the tombstone; the recipient can't.
-- =====================================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
