-- =====================================================================
--  PATCH 209 — shared posts can actually unfurl a preview
--
--  THE BUG
--
--  Sharing a post produced a link with no title, no description and no
--  thumbnail. Three separate faults, stacked, all in the same path:
--
--   1. RLS. `posts_select_visible` (patch_012) opens with
--        auth.role() = 'authenticated'
--      and the share Worker reads with the project's ANON key, so
--      auth.role() is 'anon' and EVERY row is invisible to it.
--      Measured on production before this patch:
--
--        GET /rest/v1/posts?visibility=eq.public   as anon -> []
--        GET /rest/v1/products                     as anon -> 2 rows
--
--      Products unfurl, posts do not, and that is the whole difference.
--
--   2. Wrong column. The Worker selects `content` — `public.posts` has
--      no such column. The text lives in `body`. Even with RLS opened
--      this select would have 400'd.
--
--   3. Wrong id type in the mental model. `posts.id` is UUID, not the
--      bigint the other share types use.
--
--  THE FIX, AND WHY IT IS NOT "LOOSEN THE POLICY"
--
--  Granting anon SELECT on `posts` would expose the whole public feed to
--  unauthenticated enumeration — anyone could pull every public post in
--  the app with one REST call and no account. A share card needs exactly
--  one row, by id, and only ever a public one. So: a SECURITY DEFINER
--  function that takes the id and returns the three fields the card
--  renders. No enumeration, no listing, nothing but what the Open Graph
--  tags need.
--
--  `visibility = 'public'` is enforced INSIDE the function, so a
--  friends-only or private post returns zero rows and the Worker falls
--  through to its "not found" page — the same behaviour the Worker's own
--  comment already promised but RLS was silently providing by accident.
--
--  SAFETY
--
--   * SECURITY DEFINER + a hard visibility filter, so it cannot be used
--     to read a non-public post whatever id is passed.
--   * No author identity is returned. The card says "Advent Connect ZW",
--     not who wrote it — sharing a post must not out its author to
--     whoever the link reaches.
--   * Body is truncated to 200 chars: it is a preview, and an unbounded
--     text column in an og:description is how you get a 40KB meta tag.
--   * `is_banned` authors are excluded — their content should not be the
--     thing that unfurls in a WhatsApp group.
--   * REVOKE FROM PUBLIC first. Supabase grants EXECUTE to anon and
--     authenticated explicitly, so REVOKE ... FROM PUBLIC alone does not
--     take it away — verify with has_function_privilege, not by reading
--     this file.
--
--  PREREQUISITES: patch_012 (posts_select_visible).
--  IDEMPOTENT:    yes — CREATE OR REPLACE + idempotent grants.
--
--  SHIP WITH: the matching `cloudflare/share-worker.js` change
--  (`wrangler deploy`). The Worker must call this RPC instead of
--  selecting from the table, and must read `body`, not `content`.
-- =====================================================================


CREATE OR REPLACE FUNCTION public.post_share_card(p_id uuid)
RETURNS TABLE (body text, image text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    left(COALESCE(p.body, ''), 200) AS body,
    COALESCE(
      NULLIF(p.image_url, ''),
      CASE
        WHEN array_length(p.image_urls, 1) > 0 THEN p.image_urls[1]
        ELSE ''
      END
    ) AS image
  FROM public.posts p
  JOIN public.profiles a ON a.id = p.author_id
  WHERE p.id = p_id
    AND p.visibility = 'public'
    AND a.is_banned = FALSE;
$function$;

-- Anon is the point: the share Worker has no user session.
REVOKE ALL ON FUNCTION public.post_share_card(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.post_share_card(uuid) TO anon, authenticated;
