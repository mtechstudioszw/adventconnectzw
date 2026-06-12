-- =====================================================================
--  PATCH 105 — text status (WhatsApp-style text-only stories)
--
--  Stories required media_url. Text statuses have no image — a coloured
--  background + centred text instead. media_url becomes optional and we
--  add kind ('photo' | 'text'), the text body, and a background colour.
-- =====================================================================

ALTER TABLE public.stories ALTER COLUMN media_url DROP NOT NULL;
ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'photo';
ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS text_content TEXT;
ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS background_color TEXT;
