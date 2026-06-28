-- patch_144: hymnal collections so the Hymnal tab can switch between the
-- Shona "Kristu MuNzwiyo" (~300) and the English "SDA Hymnal" (~600).
-- Reuse the existing `language` to seed it; new hymns pick a collection in the
-- admin editor.
ALTER TABLE public.hymns ADD COLUMN IF NOT EXISTS collection text;

UPDATE public.hymns
   SET collection = CASE
     WHEN lower(coalesce(language, '')) LIKE 'shona%' THEN 'kristu_munzwiyo'
     ELSE 'sda_hymnal'
   END
 WHERE collection IS NULL;

ALTER TABLE public.hymns ALTER COLUMN collection SET DEFAULT 'kristu_munzwiyo';
