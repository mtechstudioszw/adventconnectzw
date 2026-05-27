-- =====================================================================
--  PATCH 023 — Super admin role + advent_news write access
--
--  WHY: User asked for an in-app Advent News posting flow but the
--       full admin dashboard is paused. We need a lightweight way
--       to gate "Post news" on a single admin without building a
--       whole role table — until the admin module ships.
--
--  WHAT:
--   1. profiles.is_super_admin BOOLEAN DEFAULT FALSE.
--   2. Extend the advent_news INSERT / UPDATE / DELETE RLS policies
--      to also accept super_admin profiles.
-- =====================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN NOT NULL DEFAULT FALSE;

DROP POLICY IF EXISTS "advent_news_insert_admin" ON public.advent_news;
CREATE POLICY "advent_news_insert_admin"
  ON public.advent_news
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_super_admin = TRUE
    )
    OR EXISTS (
      SELECT 1 FROM public.church_admins
       WHERE user_id = auth.uid() AND status = 'approved'
    )
  );

DROP POLICY IF EXISTS "advent_news_update_admin" ON public.advent_news;
CREATE POLICY "advent_news_update_admin"
  ON public.advent_news
  FOR UPDATE
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_super_admin = TRUE
    )
  );

DROP POLICY IF EXISTS "advent_news_delete_admin" ON public.advent_news;
CREATE POLICY "advent_news_delete_admin"
  ON public.advent_news
  FOR DELETE
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_super_admin = TRUE
    )
  );

-- Mark Tanatswa's profile as super admin so the in-app posting
-- flow has an immediate authorised user. Replace this id once
-- the admin module ships with a proper assignment flow.
UPDATE public.profiles
   SET is_super_admin = TRUE
 WHERE id = '98446d00-d88f-4656-819a-8341ac0869b4';
