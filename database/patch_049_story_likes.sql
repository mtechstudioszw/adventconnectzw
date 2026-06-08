-- patch_049: story likes
-- ---------------------------------------------------------------------
-- Mirrors story_views (applied live in an earlier session): a viewer can
-- like a story; the author sees who liked. Instagram-style privacy —
-- viewers tap a heart, only the story owner sees the tally and the
-- who-liked list. Non-owners can read back ONLY their own like row so
-- the heart can render filled when they re-open the story.
--
-- The FK on user_id auto-names to story_likes_user_id_fkey, which is the
-- relationship PostgREST embeds on for the who-liked query.

CREATE TABLE IF NOT EXISTS public.story_likes (
  story_id   UUID NOT NULL REFERENCES public.stories(id)  ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, user_id)
);

CREATE INDEX IF NOT EXISTS story_likes_story_idx
  ON public.story_likes (story_id, created_at DESC);

ALTER TABLE public.story_likes ENABLE ROW LEVEL SECURITY;

-- Like / unlike only your own row.
DROP POLICY IF EXISTS "story_likes_insert_self" ON public.story_likes;
CREATE POLICY "story_likes_insert_self" ON public.story_likes
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "story_likes_delete_self" ON public.story_likes;
CREATE POLICY "story_likes_delete_self" ON public.story_likes
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Read your own like row, OR every like on a story you authored.
DROP POLICY IF EXISTS "story_likes_select_self_or_owner" ON public.story_likes;
CREATE POLICY "story_likes_select_self_or_owner" ON public.story_likes
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.stories s
      WHERE s.id = story_likes.story_id
        AND s.author_id = auth.uid()
    )
  );
