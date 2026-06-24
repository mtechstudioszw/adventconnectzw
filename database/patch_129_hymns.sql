-- =====================================================================
--  PATCH 129 — structured Hymnal (searchable by number / title / lyrics)
--
--  The Hymnal tab needs to search by hymn NUMBER, TITLE and LYRICS — which a
--  scanned PDF can't do (no text). So hymns are stored as structured rows:
--  number + title + full lyrics. This also gives a clean in-app lyrics view
--  with adjustable font size, like modern hymnal apps.
--
--  Upload-driven: the user inserts rows (e.g. the Shona hymnal) and they
--  appear in-app with no code change. `language` lets multiple hymnals
--  coexist (Shona / English) later.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.hymns (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  number       INTEGER,                 -- hymn number (nullable for extras)
  title        TEXT NOT NULL,
  lyrics       TEXT NOT NULL,           -- full lyrics, verses separated by blank lines
  language     TEXT NOT NULL DEFAULT 'Shona',
  category     TEXT,                    -- optional grouping/theme
  is_published BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS hymns_lang_number_idx
  ON public.hymns (language, number);

-- Full-text index over title + lyrics for fast lyric search at scale.
CREATE INDEX IF NOT EXISTS hymns_search_idx
  ON public.hymns USING GIN (
    to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(lyrics, ''))
  );

ALTER TABLE public.hymns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hymns_read ON public.hymns;
CREATE POLICY hymns_read ON public.hymns
  FOR SELECT TO anon, authenticated USING (is_published);
-- Writes via dashboard / service role only (curated content).
