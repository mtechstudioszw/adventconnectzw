-- =====================================================================
--  PATCH 230 — "Did you mean…": close matches when search finds nothing
--
--  Founder, 23 Aug 2026: "when it doesn't find something it should suggest
--  something close to that".
--
--  Today an unmatched search falls back to "here are people you might
--  know" — which is generic, unrelated to what was typed, and reads as the
--  app changing the subject. Someone hunting "Highfeld" (Highfield),
--  "Chitungwisa" (Chitungwiza) or a misspelled surname gets no help at all,
--  even though the intended row is one character away.
--
--  pg_trgm is already installed and there are already four GIN trigram
--  indexes in this database, so the similarity machinery is present and
--  paid for — nothing was using it for suggestions.
--
--  ## Why a threshold of 0.18
--
--  Low, deliberately. This RPC only ever runs when the normal search
--  returned NOTHING, so the alternative to a mediocre suggestion is a dead
--  end, not a better result. Being slightly too eager here costs a row the
--  member ignores; being too strict costs them the thing they were looking
--  for. The ORDER BY still puts the best match first.
--
--  ## Scope
--
--  People and churches only, and that is on purpose: they are the two
--  things members search by NAME, which is what fuzzy matching helps with.
--  Nobody misspells their way to a job listing — those searches are
--  keyword-ish, and a trigram guess at a description is noise.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE OR REPLACE FUNCTION public.search_did_you_mean(
  p_term  text,
  p_limit int DEFAULT 8
)
RETURNS TABLE (
  kind      text,   -- 'person' | 'church'
  ref_id    text,
  label     text,
  sublabel  text,
  photo_url text,
  score     real
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH term AS (SELECT btrim(coalesce(p_term, '')) AS t),
  people AS (
    SELECT 'person'::text                         AS kind,
           p.id::text                             AS ref_id,
           p.full_name                            AS label,
           COALESCE(c.name, p.city, p.province)   AS sublabel,
           p.profile_photo_url                    AS photo_url,
           similarity(p.full_name, (SELECT t FROM term)) AS score
      FROM public.profiles p
      LEFT JOIN public.churches c ON c.id = p.church_id
     WHERE (SELECT length(t) FROM term) >= 2
       AND p.is_discoverable = true
       AND COALESCE(p.is_banned, false) = false
       AND p.full_name IS NOT NULL
       -- Not is_blocked_by(): this list is names only, and calling a
       -- per-row function across the table for a fallback nobody sees most
       -- of the time is not worth it. Opening the profile still enforces
       -- every block, because that read goes through the profiles policy.
       AND similarity(p.full_name, (SELECT t FROM term)) > 0.18
  ),
  chs AS (
    SELECT 'church'::text                          AS kind,
           ch.id::text                             AS ref_id,
           ch.name                                 AS label,
           NULLIF(concat_ws(', ', ch.city, ch.province), '') AS sublabel,
           ch.profile_photo_url                    AS photo_url,
           similarity(ch.name, (SELECT t FROM term)) AS score
      FROM public.churches ch
     WHERE (SELECT length(t) FROM term) >= 2
       AND ch.name IS NOT NULL
       AND similarity(ch.name, (SELECT t FROM term)) > 0.18
  )
  SELECT * FROM (
    SELECT * FROM people
    UNION ALL
    SELECT * FROM chs
  ) u
  ORDER BY u.score DESC, u.label ASC
  LIMIT GREATEST(LEAST(p_limit, 25), 1);
$function$;

REVOKE ALL ON FUNCTION public.search_did_you_mean(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_did_you_mean(text, int) TO authenticated;

-- Trigram indexes for the two columns this searches. Without them each
-- suggestion is a sequential scan computing similarity() per row — fine at
-- 240 profiles, not fine at 2,600 churches, and worse as both grow.
CREATE INDEX IF NOT EXISTS idx_profiles_full_name_trgm
  ON public.profiles USING gin (full_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_churches_name_trgm
  ON public.churches USING gin (name gin_trgm_ops);
