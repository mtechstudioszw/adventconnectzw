-- =====================================================================
--  PATCH 166 — "Who is this?" context for the chat header
--
--  In a faith community the answer to "should I reply to this stranger"
--  is usually "do we belong to the same congregation, and do we know any
--  of the same people". The chat header could show neither.
--
--  Church name is readable client-side already. MUTUAL FRIENDS is not:
--  `friendships_select_involved` limits SELECT to rows the caller is
--  party to, so a client can read its OWN friend list and nothing else.
--  Computing an overlap needs to read the other person's friends too,
--  which is exactly what RLS is there to prevent.
--
--  So this is a SECURITY DEFINER function that returns only a COUNT —
--  never the identities. The caller learns "3 mutual friends" and cannot
--  learn who they are, which is the same trade every social app makes
--  and keeps the friend graph private.
--
--  Read-only. Adds no table and no column.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.chat_peer_context(p_other uuid)
RETURNS TABLE (church_name text, mutual_friends integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  RETURN QUERY
  WITH mine AS (
    SELECT CASE WHEN f.requester_id = auth.uid()
                THEN f.addressee_id ELSE f.requester_id END AS uid
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
  ),
  theirs AS (
    SELECT CASE WHEN f.requester_id = p_other
                THEN f.addressee_id ELSE f.requester_id END AS uid
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (f.requester_id = p_other OR f.addressee_id = p_other)
  )
  SELECT
    (SELECT c.name
       FROM public.profiles pr
       LEFT JOIN public.churches c ON c.id = pr.church_id
      WHERE pr.id = p_other)::text,
    (SELECT count(*)
       FROM mine
       JOIN theirs USING (uid)
      -- Neither party counts as a mutual friend of themselves.
      WHERE mine.uid <> auth.uid() AND mine.uid <> p_other)::integer;
END;
$$;

REVOKE ALL ON FUNCTION public.chat_peer_context(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.chat_peer_context(uuid) TO authenticated;
