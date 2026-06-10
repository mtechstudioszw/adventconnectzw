-- =====================================================================
--  PATCH 080 — allow message_type = 'product' (and 'story_reply')
--
--  Tapping "Message" on a marketplace product sends a product CARD
--  (message_type='product' + meta with the image/title/price). The
--  message_type CHECK only permitted text/image/voice/system, so the
--  card insert was rejected ("Could not send message") and only the
--  plain text (a separate path) appeared. Add 'product' (and
--  'story_reply' for replying to a status) to the allowed set.
-- =====================================================================

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_message_type_check
  CHECK (message_type = ANY (ARRAY[
    'text'::text, 'image'::text, 'voice'::text, 'system'::text,
    'product'::text, 'story_reply'::text
  ]));
