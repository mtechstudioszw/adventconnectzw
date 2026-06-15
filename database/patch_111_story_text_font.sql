-- =====================================================================
--  PATCH 111 — text-status font choice
--
--  WhatsApp-style text statuses can now pick a font. The chosen font key
--  ('poppins' / 'archivo' / 'pacifico' / 'slab') is stored alongside the
--  existing text_content + background_color so the viewer renders the same
--  font the author picked. Nullable — old statuses default to Poppins.
-- =====================================================================

ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS text_font text;
