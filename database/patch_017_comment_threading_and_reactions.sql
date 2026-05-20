-- =====================================================================
--  PATCH 017 — Comment threading + like/dislike on post comments
--
--  WHY:
--   • Threaded replies: today every post_comment is a flat row keyed only
--     to a post. Users want to reply *to a specific comment* so a
--     conversation can branch. We add `parent_comment_id` referencing
--     the parent row in the same table — depth is unbounded at the DB
--     level; the UI flattens >1 level deep into a single reply list.
--   • Reactions: a single emoji-style like was too coarse. We add a
--     small reactions table that stores either a +1 (like) or -1
--     (dislike) per (comment, user). Primary key covers the upsert
--     path and prevents duplicate votes from one user on one comment.
--
--  RLS: matches the post_comments policy — any authenticated, active
--       user can read; only the voter can insert/update/delete their
--       own row.
--
--  PREREQUISITES: schema.sql + patch_001..patch_016 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


-- ----- 1. Threading column on post_comments -------------------------
ALTER TABLE public.post_comments
  ADD COLUMN IF NOT EXISTS parent_comment_id UUID
    REFERENCES public.post_comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_post_comments_parent
  ON public.post_comments (parent_comment_id);

COMMENT ON COLUMN public.post_comments.parent_comment_id IS
  'NULL for a top-level comment on the post; otherwise references the '
  'comment this row is a reply to. The UI groups replies under their '
  'parent and renders them indented.';


-- ----- 2. Reactions table -------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_comment_reactions (
  comment_id UUID NOT NULL
    REFERENCES public.post_comments(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  value      SMALLINT NOT NULL
    CHECK (value IN (-1, 1)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_comment_reactions_user
  ON public.post_comment_reactions (user_id);

ALTER TABLE public.post_comment_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_comment_reactions_select_all"  ON public.post_comment_reactions;
DROP POLICY IF EXISTS "post_comment_reactions_insert_self" ON public.post_comment_reactions;
DROP POLICY IF EXISTS "post_comment_reactions_update_self" ON public.post_comment_reactions;
DROP POLICY IF EXISTS "post_comment_reactions_delete_self" ON public.post_comment_reactions;

CREATE POLICY "post_comment_reactions_select_all" ON public.post_comment_reactions
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "post_comment_reactions_insert_self" ON public.post_comment_reactions
  FOR INSERT WITH CHECK (
    auth.uid() = user_id AND public.user_is_active()
  );

CREATE POLICY "post_comment_reactions_update_self" ON public.post_comment_reactions
  FOR UPDATE USING (auth.uid() = user_id AND public.user_is_active())
              WITH CHECK (auth.uid() = user_id);

CREATE POLICY "post_comment_reactions_delete_self" ON public.post_comment_reactions
  FOR DELETE USING (auth.uid() = user_id);


-- ----- 3. Keep updated_at fresh on UPDATE ---------------------------
CREATE OR REPLACE FUNCTION public.touch_post_comment_reactions_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_post_comment_reactions_touch
  ON public.post_comment_reactions;
CREATE TRIGGER trg_post_comment_reactions_touch
  BEFORE UPDATE ON public.post_comment_reactions
  FOR EACH ROW EXECUTE FUNCTION
  public.touch_post_comment_reactions_updated_at();


-- =====================================================================
--  END OF PATCH 017
-- =====================================================================
