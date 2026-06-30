-- =====================================================================
--  PATCH 157 — youtube_search: match as-you-type (substring), not just
--  whole words.
--
--  The original used only websearch_to_tsquery, which needs COMPLETE
--  words — typing "sab" returned nothing until you finished "sabbath",
--  so search felt broken. Add ILIKE substring matching (title +
--  channel) so partial input returns results immediately, keep the
--  full-text match as a fallback, and rank exact/prefix title hits first.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.youtube_search(
  p_query TEXT,
  p_limit INT DEFAULT 30,
  p_offset INT DEFAULT 0
)
RETURNS SETOF public.youtube_videos
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT v.*
    FROM public.youtube_videos v
    JOIN public.youtube_channels c ON c.channel_id = v.channel_id
   WHERE c.status = 'active'
     AND v.is_hidden = false
     AND (
       btrim(coalesce(p_query, '')) = ''
       OR v.title ILIKE '%' || p_query || '%'
       OR v.channel_title ILIKE '%' || p_query || '%'
       OR v.search_tsv @@ websearch_to_tsquery('english', p_query)
     )
   ORDER BY
     (CASE
        WHEN v.title ILIKE p_query || '%' THEN 0       -- title starts with query
        WHEN v.title ILIKE '%' || p_query || '%' THEN 1 -- title contains query
        ELSE 2                                          -- channel / full-text only
      END),
     v.published_at DESC
   LIMIT GREATEST(p_limit, 1) OFFSET GREATEST(p_offset, 0);
$$;
