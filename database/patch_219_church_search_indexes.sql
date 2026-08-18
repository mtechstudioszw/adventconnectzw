-- =====================================================================
--  PATCH 219 — make church search survive the global directory
--
--  Groundwork for the ASTR / OrgMast import: 106,936 churches + 78,061
--  companies worldwide against the ~2,600 Zimbabwean rows here today. A
--  41x jump.
--
--  Two things break at that size, and both are fixed here rather than
--  after the import, when the app would already be unusable:
--
--   1. `name ILIKE '%harare%'` is a SEQUENTIAL SCAN. It is fine over 2,600
--      rows and is not fine over 185,000 — every keystroke in the church
--      picker would walk the whole table. pg_trgm turns exactly that
--      pattern (leading-wildcard ILIKE) into an index lookup, which is why
--      a plain B-tree is no use: a B-tree cannot serve `%foo%`.
--
--   2. The picker's real query is "churches in MY country matching this
--      text", so country needs to be usable alongside the text match.
--      patch_213 already indexed `country` and `(country, city)`.
--
--  NOT DONE HERE: the nearest-first sort on churches_screen still pulls
--  rows and sorts client-side by distance. That is the next thing to break
--  after an import and it needs a real geo query (earthdistance or PostGIS)
--  — a bigger change, and pointless until the rows actually exist.
-- =====================================================================

-- Supabase ships pg_trgm; this is a no-op when it is already installed.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN over trigrams: serves ILIKE '%term%' on name and city, which is what
-- both the directory search and the onboarding picker actually send.
CREATE INDEX IF NOT EXISTS idx_churches_name_trgm
  ON public.churches USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_churches_city_trgm
  ON public.churches USING gin (city gin_trgm_ops);

-- The picker lists alphabetically within a country when the box is empty.
CREATE INDEX IF NOT EXISTS idx_churches_country_name
  ON public.churches (country, name);

-- ---------------------------------------------------------------------
--  Verification — run these and read the output.
-- ---------------------------------------------------------------------
-- SELECT indexname FROM pg_indexes
--  WHERE schemaname='public' AND tablename='churches'
--  ORDER BY indexname;
--   -- expect the three above plus patch_213's country indexes
--
-- EXPLAIN ANALYZE
--   SELECT id, name, city FROM public.churches
--    WHERE country = 'ZW' AND name ILIKE '%avond%'
--    ORDER BY name LIMIT 40;
--   -- At 2,600 rows Postgres may still choose a seq scan and be right to;
--   -- the point is that after the import it HAS the option not to.
