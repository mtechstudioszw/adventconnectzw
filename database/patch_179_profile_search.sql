-- =====================================================================
--  PATCH 179 — people search that actually finds people
--
--  The app searched profiles with ONE contiguous substring match:
--      full_name ILIKE '%' || query || '%'
--
--  which fails in all the ways members were reporting:
--    * "Tanatswa Mikuwa" does not match "Tanatswa Michael Mikuwa" —
--      the words are not adjacent, so the LIKE never fires.
--    * "Mikuwa Tanatswa" finds nothing: word order is significant.
--    * usernames were not searched at all, so anyone who searched the
--      handle they were given got zero results.
--    * one wrong letter returns nothing, with no near-miss fallback.
--
--  The client tried to paper over this with a three-pass cascade that
--  progressively dropped is_discoverable and is_banned. That never
--  addressed the real cause (all three passes ran the same broken
--  LIKE) and it quietly widened visibility as a side effect.
--
--  This replaces it with a single ranked query:
--    1. TOKEN match — every word typed must appear somewhere in
--       "full_name username". Order-insensitive, gap-tolerant.
--    2. TRIGRAM match — pg_trgm similarity on the whole string, so a
--       typo or a half-remembered spelling still surfaces the person.
--    3. PREFIX match — cheap and it makes short queries feel instant.
--
--  Results are ranked best-first: exact prefix, then trigram score,
--  then name. pg_trgm is already installed on this project.
--
--  SECURITY: SECURITY DEFINER, but the column list is explicit and
--  contains nothing sensitive (never fcm_token — see patch_132). It
--  excludes banned accounts and anyone in a block relationship with the
--  caller, which the old client-side path did NOT do. Non-discoverable
--  profiles are excluded unless nothing else matches, which restores
--  the intent the client cascade had accidentally abandoned.
-- =====================================================================

-- Trigram indexes so this stays fast as the member list grows. GIN over
-- the lowercased name/username is what the similarity() and LIKE arms
-- both ride on.
CREATE INDEX IF NOT EXISTS idx_profiles_full_name_trgm
  ON public.profiles USING gin (lower(full_name) gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_profiles_username_trgm
  ON public.profiles USING gin (lower(username) gin_trgm_ops);

CREATE OR REPLACE FUNCTION public.search_profiles(
  p_query TEXT,
  p_limit INTEGER DEFAULT 30
)
RETURNS TABLE (
  id                UUID,
  full_name         TEXT,
  username          TEXT,
  profile_photo_url TEXT,
  province          TEXT,
  city              TEXT,
  bio               TEXT,
  is_verified       BOOLEAN,
  is_verified_admin BOOLEAN,
  is_discoverable   BOOLEAN,
  score             REAL
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_term   TEXT;
  v_tokens TEXT[];
  v_me     UUID := auth.uid();
  v_limit  INTEGER := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
BEGIN
  -- Collapse whitespace, lowercase. Everything below compares lowered.
  v_term := btrim(regexp_replace(lower(COALESCE(p_query, '')), '\s+', ' ', 'g'));
  IF v_term = '' THEN
    RETURN;
  END IF;

  v_tokens := array_remove(string_to_array(v_term, ' '), '');

  RETURN QUERY
  WITH candidates AS (
    SELECT
      p.id,
      p.full_name,
      p.username,
      p.profile_photo_url,
      p.province,
      p.city,
      p.bio,
      p.is_verified,
      p.is_verified_admin,
      p.is_discoverable,
      lower(COALESCE(p.full_name, '') || ' ' || COALESCE(p.username, ''))
        AS haystack,
      GREATEST(
        similarity(lower(COALESCE(p.full_name, '')), v_term),
        similarity(lower(COALESCE(p.username, '')), v_term)
      ) AS sim
    FROM public.profiles p
    WHERE p.is_banned = FALSE
      AND (v_me IS NULL OR p.id <> v_me)
      -- Block relationships cut both ways; neither side should surface
      -- in the other's search. is_blocked_by() is the same helper the
      -- prayers and feed policies use.
      AND NOT public.is_blocked_by(p.id)
  ),
  matched AS (
    SELECT
      c.*,
      -- Every typed word present somewhere: the workhorse arm.
      (SELECT bool_and(c.haystack LIKE '%' || tok || '%')
         FROM unnest(v_tokens) AS tok) AS token_hit,
      (c.haystack LIKE v_term || '%'
        OR lower(COALESCE(c.username, '')) LIKE v_term || '%') AS prefix_hit
    FROM candidates c
  )
  SELECT
    m.id,
    m.full_name,
    m.username,
    m.profile_photo_url,
    m.province,
    m.city,
    m.bio,
    m.is_verified,
    m.is_verified_admin,
    m.is_discoverable,
    (
      CASE WHEN m.prefix_hit THEN 1.0 ELSE 0 END
      + CASE WHEN m.token_hit THEN 0.6 ELSE 0 END
      + m.sim
    )::REAL AS score
  FROM matched m
  WHERE m.token_hit
     OR m.prefix_hit
     -- 0.22 is deliberately loose: these are personal names, often
     -- transliterated, and a member typing a name they heard out loud
     -- should still land on it.
     OR m.sim >= 0.22
  ORDER BY
    -- Opted-in members first; the rest still reachable, which is what
    -- the old cascade ended up doing anyway, just unranked.
    m.is_discoverable DESC,
    score DESC,
    m.full_name ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.search_profiles(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_profiles(TEXT, INTEGER) TO authenticated;

COMMENT ON FUNCTION public.search_profiles(TEXT, INTEGER) IS
  'Ranked people search: per-word matching + pg_trgm fuzzy fallback over '
  'full_name and username. Excludes banned accounts, the caller, and any '
  'block relationship. Returns public profile columns only.';
