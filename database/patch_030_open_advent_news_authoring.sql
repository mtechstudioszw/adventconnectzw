-- patch_030_open_advent_news_authoring.sql
--
-- WHAT:  Open Advent News authoring to every signed-in user. Until now
--        only approved church admins could publish. Founder direction
--        (2026-05-27) is to let any member post so the surface fills up
--        organically. Update / Delete are still author-scoped (only the
--        person who wrote a story can edit or remove it).
--
-- IDEMPOTENT:  yes.
--
-- =============================================================

DROP POLICY IF EXISTS "advent_news_insert_admin" ON public.advent_news;
DROP POLICY IF EXISTS "advent_news_insert_member" ON public.advent_news;

CREATE POLICY "advent_news_insert_member"
  ON public.advent_news
  FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND auth.uid() = author_id
  );
