-- =====================================================================
--  PATCH 128 — Library (Hymnal / Music / EGW books) catalog + storage
--
--  Powers the in-app Library screen's Hymnal, Music and EGW Books tabs.
--  (The Bible tab is a bundled offline KJV asset, not in the DB.)
--
--  Upload-driven: the user drops a PDF/audio file into the `library`
--  storage bucket and inserts a library_items row — it appears in the app
--  with no code change. New EGW books = just more rows.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.library_items (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind             TEXT NOT NULL CHECK (kind IN ('hymnal', 'music', 'egw_book')),
  title            TEXT NOT NULL,
  author           TEXT,                 -- e.g. 'Ellen G. White'
  description      TEXT,
  language         TEXT,                 -- e.g. 'Shona', 'English'
  cover_url        TEXT,                 -- optional thumbnail
  file_url         TEXT NOT NULL,        -- PDF (hymnal/egw_book) or audio (music)
  duration_seconds INTEGER,             -- music only
  sort_order       INTEGER NOT NULL DEFAULT 0,
  is_published     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS library_items_kind_order_idx
  ON public.library_items (kind, sort_order, created_at DESC);

ALTER TABLE public.library_items ENABLE ROW LEVEL SECURITY;

-- Everyone can read published items (the library is public content).
DROP POLICY IF EXISTS library_items_read ON public.library_items;
CREATE POLICY library_items_read ON public.library_items
  FOR SELECT TO anon, authenticated USING (is_published);
-- No write policy: content is curated via the Supabase dashboard /
-- service role only (the user uploads the files + adds the rows).

-- Public storage bucket for the PDFs / audio / covers.
INSERT INTO storage.buckets (id, name, public)
VALUES ('library', 'library', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- Public read of objects in the library bucket.
DROP POLICY IF EXISTS library_objects_read ON storage.objects;
CREATE POLICY library_objects_read ON storage.objects
  FOR SELECT TO anon, authenticated USING (bucket_id = 'library');
