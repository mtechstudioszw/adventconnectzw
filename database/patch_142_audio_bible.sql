-- patch_142: add 'audio_bible' as a Library content kind (upload-driven audio,
-- played through the existing music player). Extends the kind CHECK constraint.
ALTER TABLE public.library_items DROP CONSTRAINT IF EXISTS library_items_kind_check;
ALTER TABLE public.library_items ADD CONSTRAINT library_items_kind_check
  CHECK (kind = ANY (ARRAY['hymnal'::text, 'music'::text, 'egw_book'::text, 'audio_bible'::text]));
