-- =====================================================================
--  PATCH 012 — Feed privacy
--
--  WHY:  Two product asks landed at the same time:
--          1. Stories should only be visible to friends (accepted).
--          2. Posts should let the author choose 'public' (everyone)
--             vs 'friends_only' (only accepted friends + the author).
--
--  RLS:   Both filters happen server-side so the client can issue a
--         simple `select *` and trust the result. Adding the visibility
--         column required a DEFAULT to populate existing rows.
--
--  PREREQUISITES: schema.sql + patch_001..patch_011 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- posts.visibility — 'public' (default) | 'friends_only'
-- ---------------------------------------------------------------------
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public'
    CHECK (visibility IN ('public', 'friends_only'));

CREATE INDEX IF NOT EXISTS idx_posts_visibility
  ON public.posts (visibility);


-- ---------------------------------------------------------------------
-- Replace the broad posts SELECT policy with one that respects
-- visibility. Public posts: anyone authenticated. Friends-only posts:
-- the author + users in an accepted friendship with the author.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "posts_select_all" ON public.posts;
DROP POLICY IF EXISTS "posts_select_visible" ON public.posts;

CREATE POLICY "posts_select_visible" ON public.posts
  FOR SELECT USING (
    auth.role() = 'authenticated' AND (
      visibility = 'public'
      OR author_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.friendships f
        WHERE f.status = 'accepted'
          AND (
            (f.requester_id = auth.uid() AND f.addressee_id = posts.author_id)
            OR (f.addressee_id = auth.uid() AND f.requester_id = posts.author_id)
          )
      )
    )
  );


-- ---------------------------------------------------------------------
-- Stories: friends only. Authors can always see their own.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "stories_select_active" ON public.stories;

CREATE POLICY "stories_select_active" ON public.stories
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND expires_at > NOW()
    AND (
      author_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.friendships f
        WHERE f.status = 'accepted'
          AND (
            (f.requester_id = auth.uid() AND f.addressee_id = stories.author_id)
            OR (f.addressee_id = auth.uid() AND f.requester_id = stories.author_id)
          )
      )
    )
  );


-- =====================================================================
--  END OF PATCH 012
-- =====================================================================
