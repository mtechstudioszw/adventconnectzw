-- =====================================================================
--  PATCH 064 — message.meta (product cards in chat)
--
--  "Message seller" tagged a product, but on send only the text went
--  through and the image preview vanished. Store the product reference
--  on the message (message_type='product', meta jsonb) so it sends as a
--  tappable product card that opens the listing.
-- =====================================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS meta JSONB;
