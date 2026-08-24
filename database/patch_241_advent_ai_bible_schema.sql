-- =====================================================================
--  PATCH 241 — Advent AI: the Bible corpus (schema)
--
--  One of the two parts the original Advent AI roadmap promised and
--  never delivered. Without it the model quotes scripture from memory,
--  which is exactly the fabrication the brief (§10) forbids — and in a
--  Bible app, a wrong verse is the worst possible bug.
--
--  ## Why the text has to live here
--
--  The app already ships the KJV: `assets/bible/kjv.json`, 66 books,
--  31,102 verses, read by `lib/services/bible_service.dart`. That asset
--  is on the PHONE. The edge function runs on a server and cannot read
--  it, so grounding the model needs the same text in Postgres.
--
--  This duplicates the KJV rather than replacing the asset. That is
--  deliberate: the Bible tab must keep working fully offline, which is
--  the whole reason the asset exists. Two copies of a fixed 400-year-old
--  public-domain text will not drift.
--
--  ## What "grounded" means here
--
--  The edge function looks up the passage BEFORE calling the model and
--  passes the real text in, wrapped as untrusted data (see
--  `wrapRetrieved` in prompt.ts). The model then quotes what it was
--  given instead of what it remembers. When no passage is found, the
--  prompt's standing rule applies: refer to the reference, do not
--  produce quotation marks around remembered wording.
--
--  ## Public domain
--
--  The KJV is public domain worldwide. No licence applies and none is
--  implied for any other translation — do NOT load a modern translation
--  into this table without checking its licence. Most are not free to
--  redistribute, and an API-served translation is a different design.
--
--  The data itself arrives in patches 242+, split because the whole
--  corpus is ~6MB of SQL and the management API takes one patch as a
--  single request body.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  The corpus
--
--  One row per verse. Flat rather than book/chapter nested, because
--  every access pattern here is "give me this range" or "find this
--  phrase", and both are simpler against a flat table.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bible_verses (
  id            BIGSERIAL PRIMARY KEY,

  -- 'kjv'. Present from the start so a second translation is an INSERT
  -- rather than a migration, even though only one is licensed today.
  translation   TEXT   NOT NULL DEFAULT 'kjv',

  -- 1-66, canonical order. The ordering key for everything.
  book_number   SMALLINT NOT NULL,
  book_name     TEXT   NOT NULL,

  -- 1-based, unlike the asset's 0-based arrays. The asset's indices are
  -- an implementation detail of a JSON file; every human reference in
  -- the world is 1-based, and converting once on load is better than
  -- converting at every call site.
  chapter       SMALLINT NOT NULL,
  verse         SMALLINT NOT NULL,

  text          TEXT   NOT NULL,

  CONSTRAINT bible_verses_unique
    UNIQUE (translation, book_number, chapter, verse)
);

-- Range reads: "John 3:16-18".
CREATE INDEX IF NOT EXISTS bible_verses_ref_idx
  ON public.bible_verses (translation, book_number, chapter, verse);

-- Phrase search. English stemming, so "forgave" finds "forgive".
CREATE INDEX IF NOT EXISTS bible_verses_fts_idx
  ON public.bible_verses
  USING GIN (to_tsvector('english', text));

-- Book-name lookup is case-insensitive and prefix-friendly so "john",
-- "John" and "joh" all resolve.
CREATE INDEX IF NOT EXISTS bible_verses_book_lower_idx
  ON public.bible_verses (lower(book_name));

-- ---------------------------------------------------------------------
--  Book aliases
--
--  People and models write "Ps", "Psalm", "Psalms", "1 Cor", "I
--  Corinthians", "Rev". Rather than a regex thicket in the edge
--  function, aliases are data.
--
--  Seeded in patch 242 alongside the verses, so the corpus and the names
--  that reach it land together.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bible_book_aliases (
  alias        TEXT     PRIMARY KEY,   -- lowercase, no punctuation
  book_number  SMALLINT NOT NULL,
  book_name    TEXT     NOT NULL
);

-- ---------------------------------------------------------------------
--  Normalise a reference fragment to a book number.
--
--  Strips punctuation and collapses whitespace so "1 Cor.", "1cor" and
--  "I Corinthians" all land on the same row. Returns NULL when nothing
--  matches — the caller must treat that as "no passage", never as
--  "book 1".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bible_book_number(p_name TEXT)
RETURNS SMALLINT
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  WITH norm AS (
    SELECT regexp_replace(
             lower(trim(COALESCE(p_name, ''))),
             '[^a-z0-9]', '', 'g'
           ) AS k
  )
  SELECT a.book_number
    FROM public.bible_book_aliases a, norm
   WHERE a.alias = norm.k
   LIMIT 1;
$$;

-- ---------------------------------------------------------------------
--  Fetch a passage.
--
--  The function the edge function calls before every scripture answer.
--  Bounded by p_limit so a request for "Psalms" cannot pull 2,461 verses
--  into a prompt and blow the context budget (and the bill).
--
--  p_end_verse NULL means "just p_verse". p_verse NULL means "the whole
--  chapter", still capped.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bible_passage(
  p_book        TEXT,
  p_chapter     INT,
  p_verse       INT DEFAULT NULL,
  p_end_verse   INT DEFAULT NULL,
  p_translation TEXT DEFAULT 'kjv',
  p_limit       INT DEFAULT 25
)
RETURNS TABLE (
  reference TEXT,
  book_name TEXT,
  chapter   SMALLINT,
  verse     SMALLINT,
  text      TEXT
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT
    v.book_name || ' ' || v.chapter || ':' || v.verse AS reference,
    v.book_name, v.chapter, v.verse, v.text
  FROM public.bible_verses v
  WHERE v.translation = COALESCE(p_translation, 'kjv')
    AND v.book_number = public.bible_book_number(p_book)
    AND v.chapter     = p_chapter
    AND (p_verse IS NULL OR v.verse >= p_verse)
    AND (
      p_verse IS NULL
      OR v.verse <= COALESCE(p_end_verse, p_verse)
    )
  ORDER BY v.verse
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 25), 50), 1);
$$;

-- ---------------------------------------------------------------------
--  Search by phrase.
--
--  For "where does the Bible talk about..." — the model gets real
--  candidate verses rather than inventing a reference that sounds right.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bible_search(
  p_query       TEXT,
  p_translation TEXT DEFAULT 'kjv',
  p_limit       INT DEFAULT 10
)
RETURNS TABLE (
  reference TEXT,
  book_name TEXT,
  chapter   SMALLINT,
  verse     SMALLINT,
  text      TEXT,
  rank      REAL
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT
    v.book_name || ' ' || v.chapter || ':' || v.verse AS reference,
    v.book_name, v.chapter, v.verse, v.text,
    ts_rank(to_tsvector('english', v.text),
            websearch_to_tsquery('english', p_query)) AS rank
  FROM public.bible_verses v
  WHERE v.translation = COALESCE(p_translation, 'kjv')
    AND to_tsvector('english', v.text)
        @@ websearch_to_tsquery('english', p_query)
  ORDER BY rank DESC, v.book_number, v.chapter, v.verse
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 10), 25), 1);
$$;

-- ---------------------------------------------------------------------
--  RLS + grants
--
--  Scripture is public and identical for everyone, so RLS is a single
--  permissive read policy rather than an ownership rule. It is still
--  ENABLED — a table with RLS off is invisible to the linter that checks
--  for tables with RLS off, and the next person adding a table by
--  copying this one should copy a correct example.
--
--  Read-only for clients: no INSERT/UPDATE/DELETE to anyone but
--  service_role. A member editing scripture is not a feature.
-- ---------------------------------------------------------------------
ALTER TABLE public.bible_verses       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bible_book_aliases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bible_verses_read ON public.bible_verses;
CREATE POLICY bible_verses_read ON public.bible_verses
  FOR SELECT USING (true);

DROP POLICY IF EXISTS bible_book_aliases_read ON public.bible_book_aliases;
CREATE POLICY bible_book_aliases_read ON public.bible_book_aliases
  FOR SELECT USING (true);

REVOKE ALL ON public.bible_verses       FROM anon, authenticated;
REVOKE ALL ON public.bible_book_aliases FROM anon, authenticated;

GRANT SELECT ON public.bible_verses       TO anon, authenticated;
GRANT SELECT ON public.bible_book_aliases TO anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.bible_passage(TEXT, INT, INT, INT, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.bible_search(TEXT, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.bible_book_number(TEXT) TO authenticated;

-- ---------------------------------------------------------------------
--  Verification
--
--  Deliberately does NOT assert a row count — the data lands in later
--  patches, and failing here would make this patch un-appliable on its
--  own. Patch 242's own verification checks the corpus is complete.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'bible_passage'
  ) THEN
    RAISE EXCEPTION 'patch 241: bible_passage missing';
  END IF;

  RAISE NOTICE
    'patch 241 OK — corpus schema ready; load the text with patch 242+';
END $$;
