-- =====================================================================
--  PATCH 044 — Post/prayer owner can delete comments (tester bug #6)
--
--  Today: post_comments_delete_self / prayer_responses_delete_self let
--  a user delete their OWN comment. There's no way for the owner of a
--  post (or prayer) to remove someone else's comment on their content.
--  This adds that — Facebook-style "your house, your rules".
--
--  IDEMPOTENT: DROP POLICY IF EXISTS before CREATE.
-- =====================================================================

-- ----- Post owner can delete any comment on their post --------------
DROP POLICY IF EXISTS post_comments_delete_post_owner ON public.post_comments;
CREATE POLICY post_comments_delete_post_owner
  ON public.post_comments
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
       WHERE p.id = post_comments.post_id
         AND p.author_id = auth.uid()
    )
  );

-- ----- Prayer owner can delete any response on their prayer ---------
DROP POLICY IF EXISTS prayer_responses_delete_prayer_owner ON public.prayer_responses;
CREATE POLICY prayer_responses_delete_prayer_owner
  ON public.prayer_responses
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.prayers pr
       WHERE pr.id = prayer_responses.prayer_id
         AND pr.author_id = auth.uid()
    )
  );
