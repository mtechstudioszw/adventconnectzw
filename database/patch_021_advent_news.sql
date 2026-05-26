-- =====================================================================
--  PATCH 021 — Advent News
--
--  WHY: Users asked for a dedicated, editorially-curated news surface
--       distinct from user-generated posts. "What's trending in the
--       Adventist circle in Zimbabwe" — Conference announcements,
--       camp meeting recaps, GC-level news, evangelism milestones,
--       newsworthy events. The home post feed is community chatter;
--       this is publication-style content.
--
--  WHAT:
--   1. Public table `advent_news` with title/summary/body/cover/
--      category/source/pinned/published_at/author.
--   2. Six fixed categories matching how Zim members talk about
--      Adventist news (trending, announcements, global_sda, etc).
--   3. Tight RLS: anyone authenticated can SELECT (so every member
--      can read). INSERT/UPDATE/DELETE require either an approved
--      church_admins row (any church) OR a super-admin role via
--      conference_admins. Until those tables ship widely, the
--      service_role can also write directly (Supabase dashboard /
--      pg_cron / Edge Function flows).
--   4. Indexes for the two query patterns the app issues:
--      latest-published-first, and by-category.
--
--  PREREQUISITES: schema.sql.
--  IDEMPOTENT:    yes — all guards on IF NOT EXISTS / DROP IF EXISTS.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.advent_news (
  id                BIGSERIAL PRIMARY KEY,
  title             TEXT NOT NULL CHECK (char_length(title) BETWEEN 4 AND 200),
  summary           TEXT NOT NULL CHECK (char_length(summary) BETWEEN 10 AND 400),
  body              TEXT CHECK (body IS NULL OR char_length(body) <= 10000),
  cover_photo_url   TEXT,
  category          TEXT NOT NULL DEFAULT 'general',
  source_url        TEXT,
  source_label      TEXT,
  author_id         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_pinned         BOOLEAN NOT NULL DEFAULT FALSE,
  published_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.advent_news
  DROP CONSTRAINT IF EXISTS advent_news_category_chk;

ALTER TABLE public.advent_news
  ADD CONSTRAINT advent_news_category_chk
  CHECK (category IN (
    'trending',
    'announcement',
    'global_sda',
    'event_recap',
    'spiritual',
    'general'
  ));

CREATE INDEX IF NOT EXISTS idx_advent_news_published_at
  ON public.advent_news (published_at DESC, is_pinned DESC);
CREATE INDEX IF NOT EXISTS idx_advent_news_category
  ON public.advent_news (category, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_advent_news_pinned
  ON public.advent_news (is_pinned) WHERE is_pinned = TRUE;

DROP TRIGGER IF EXISTS trg_advent_news_updated_at ON public.advent_news;
CREATE TRIGGER trg_advent_news_updated_at
  BEFORE UPDATE ON public.advent_news
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.advent_news ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "advent_news_select_authenticated" ON public.advent_news;
CREATE POLICY "advent_news_select_authenticated"
  ON public.advent_news
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Authors are limited to anyone the project has approved as a
-- church admin or conference admin. The expressions reference
-- tables that already exist (patch_002 + patch_010); if those
-- aren't installed the WHERE clause just returns no rows and
-- writes go through service_role only.
DROP POLICY IF EXISTS "advent_news_insert_admin" ON public.advent_news;
CREATE POLICY "advent_news_insert_admin"
  ON public.advent_news
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.church_admins
       WHERE user_id = auth.uid()
         AND status = 'approved'
    )
    OR EXISTS (
      SELECT 1 FROM public.conference_admins
       WHERE user_id = auth.uid()
         AND is_active = TRUE
    )
  );

DROP POLICY IF EXISTS "advent_news_update_admin" ON public.advent_news;
CREATE POLICY "advent_news_update_admin"
  ON public.advent_news
  FOR UPDATE
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.conference_admins
       WHERE user_id = auth.uid()
         AND is_active = TRUE
    )
  );

DROP POLICY IF EXISTS "advent_news_delete_admin" ON public.advent_news;
CREATE POLICY "advent_news_delete_admin"
  ON public.advent_news
  FOR DELETE
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.conference_admins
       WHERE user_id = auth.uid()
         AND is_active = TRUE
    )
  );
