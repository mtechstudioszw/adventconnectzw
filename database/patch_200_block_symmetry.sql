-- =====================================================================
--  PATCH 200 — blocking is symmetric
--
--  THE BUG
--
--  patch_071 hides posts/stories/prayers from a blocked viewer with a
--  RESTRICTIVE policy over `is_blocked_by(author_id)`. That helper asks
--  exactly one question:
--
--      blocker_id = p_author AND blocked_id = auth.uid()
--      -- "has the AUTHOR blocked ME?"
--
--  So the protection only ever ran one way:
--
--    * They block you  -> their content disappears from your feed.  OK.
--    * YOU block them  -> blocker_id is you, not them, so this is false
--                         and THEIR CONTENT STAYS IN YOUR FEED.
--
--  Which is backwards from why anyone blocks: you block someone to stop
--  seeing them. Today the person doing the blocking gets no relief at
--  all in the feed, in stories or on the prayer wall — only the person
--  who was blocked is affected. (Founder, Aug 2026: "check how the block
--  system works n fix it".)
--
--  THE FIX
--
--  One function. Both policies and all three tables read through it, so
--  making the question symmetric fixes posts, stories and prayers at
--  once and nothing can be left half-migrated. Signature is unchanged,
--  so CREATE OR REPLACE is enough and no policy is touched — the less
--  this patch moves, the less there is to get wrong on a RESTRICTIVE
--  policy that gates the whole feed.
--
--  SAFETY
--
--  * Applied when `blocked_users` held ZERO rows, so the new predicate
--    returns exactly what the old one returned (false, for everybody)
--    and no post can vanish on deploy. The change only starts having an
--    effect the first time someone actually blocks someone.
--  * `auth.uid()` is NULL for anon: both branches are then false, so an
--    unauthenticated read is unaffected — same as before.
--  * `blocked_users_not_self` CHECK already forbids blocking yourself,
--    so an author can never hide their own content from themselves.
--  * STABLE + SECURITY DEFINER retained: the policy has to read rows the
--    viewer cannot see under blocked_users' own RLS.
--
--  RLS: no policy created, altered or dropped.
--  IDEMPOTENT: yes.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.is_blocked_by(p_author UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker_id = p_author     AND b.blocked_id = auth.uid())
        OR (b.blocker_id = auth.uid()   AND b.blocked_id = p_author)
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;

-- Unchanged from patch_071, restated so a fresh apply of this file alone
-- leaves the grant correct.
REVOKE ALL ON FUNCTION public.is_blocked_by(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_blocked_by(UUID) TO authenticated;
