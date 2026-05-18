-- =====================================================================
--  PATCH 011 — Facebook-style home feed (posts, stories, friendships)
--
--  WHY:  The home tab is evolving into a community feed:
--          • posts          — permanent updates from members
--          • stories        — 24h ephemeral image + caption
--          • post_likes     — Facebook-style heart on a post
--          • post_comments  — threaded discussion on a post
--          • friendships    — bidirectional friend graph (pending/accepted)
--
--  RLS:   Every authenticated, active user may read posts/stories/comments
--         and the social graph. INSERT/DELETE/UPDATE are scoped to the
--         row's owner via auth.uid().
--
--  STORAGE buckets:
--          post_photos    public  ~1 MB
--          story_photos   public  ~1 MB
--
--  PREREQUISITES: schema.sql + patch_001..patch_010 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Posts (permanent)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body         TEXT CHECK (body IS NULL OR char_length(body) <= 2000),
  image_url    TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (body IS NOT NULL OR image_url IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_posts_created_at
  ON public.posts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_author
  ON public.posts (author_id, created_at DESC);

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "posts_select_all"   ON public.posts;
DROP POLICY IF EXISTS "posts_insert_self"  ON public.posts;
DROP POLICY IF EXISTS "posts_delete_self"  ON public.posts;
DROP POLICY IF EXISTS "posts_update_self"  ON public.posts;

CREATE POLICY "posts_select_all" ON public.posts
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "posts_insert_self" ON public.posts
  FOR INSERT WITH CHECK (
    auth.uid() = author_id AND public.user_is_active()
  );

CREATE POLICY "posts_update_self" ON public.posts
  FOR UPDATE USING (auth.uid() = author_id AND public.user_is_active())
              WITH CHECK (auth.uid() = author_id AND public.user_is_active());

CREATE POLICY "posts_delete_self" ON public.posts
  FOR DELETE USING (auth.uid() = author_id);


-- ---------------------------------------------------------------------
-- Post likes (one row per (post, user))
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_likes (
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_likes_user
  ON public.post_likes (user_id);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_likes_select_all"  ON public.post_likes;
DROP POLICY IF EXISTS "post_likes_insert_self" ON public.post_likes;
DROP POLICY IF EXISTS "post_likes_delete_self" ON public.post_likes;

CREATE POLICY "post_likes_select_all" ON public.post_likes
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "post_likes_insert_self" ON public.post_likes
  FOR INSERT WITH CHECK (
    auth.uid() = user_id AND public.user_is_active()
  );

CREATE POLICY "post_likes_delete_self" ON public.post_likes
  FOR DELETE USING (auth.uid() = user_id);


-- ---------------------------------------------------------------------
-- Post comments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_comments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  author_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body       TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_post_comments_post
  ON public.post_comments (post_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_post_comments_author
  ON public.post_comments (author_id);

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_comments_select_all"  ON public.post_comments;
DROP POLICY IF EXISTS "post_comments_insert_self" ON public.post_comments;
DROP POLICY IF EXISTS "post_comments_delete_self" ON public.post_comments;

CREATE POLICY "post_comments_select_all" ON public.post_comments
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "post_comments_insert_self" ON public.post_comments
  FOR INSERT WITH CHECK (
    auth.uid() = author_id AND public.user_is_active()
  );

CREATE POLICY "post_comments_delete_self" ON public.post_comments
  FOR DELETE USING (auth.uid() = author_id);


-- ---------------------------------------------------------------------
-- Stories (24h ephemeral)
-- expires_at defaults to created_at + 24h. We do *not* auto-delete rows
-- here — the feed query filters by `expires_at > now()`. A weekly cron
-- can purge old rows later if storage cost becomes a concern.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  media_url   TEXT NOT NULL,
  caption     TEXT CHECK (caption IS NULL OR char_length(caption) <= 200),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_stories_expires_at
  ON public.stories (expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_stories_author
  ON public.stories (author_id, created_at DESC);

ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stories_select_active"   ON public.stories;
DROP POLICY IF EXISTS "stories_insert_self"     ON public.stories;
DROP POLICY IF EXISTS "stories_delete_self"     ON public.stories;

-- Anyone authenticated can read active stories; expired ones stay hidden.
CREATE POLICY "stories_select_active" ON public.stories
  FOR SELECT USING (
    auth.role() = 'authenticated' AND expires_at > NOW()
  );

CREATE POLICY "stories_insert_self" ON public.stories
  FOR INSERT WITH CHECK (
    auth.uid() = author_id AND public.user_is_active()
  );

CREATE POLICY "stories_delete_self" ON public.stories
  FOR DELETE USING (auth.uid() = author_id);


-- ---------------------------------------------------------------------
-- Friendships
-- Pair uniqueness is enforced via a functional unique index so that
-- (A→B) and (B→A) cannot both exist at once.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.friendships (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  addressee_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','accepted','declined')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (requester_id <> addressee_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_pair
  ON public.friendships (
    LEAST(requester_id, addressee_id),
    GREATEST(requester_id, addressee_id)
  );

CREATE INDEX IF NOT EXISTS idx_friendships_requester
  ON public.friendships (requester_id, status);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee
  ON public.friendships (addressee_id, status);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "friendships_select_involved"   ON public.friendships;
DROP POLICY IF EXISTS "friendships_insert_requester"  ON public.friendships;
DROP POLICY IF EXISTS "friendships_update_involved"   ON public.friendships;
DROP POLICY IF EXISTS "friendships_delete_involved"   ON public.friendships;

-- Either party can see rows that involve them.
CREATE POLICY "friendships_select_involved" ON public.friendships
  FOR SELECT USING (
    auth.uid() = requester_id OR auth.uid() = addressee_id
  );

-- Only the requester creates the row, and only while pending.
CREATE POLICY "friendships_insert_requester" ON public.friendships
  FOR INSERT WITH CHECK (
    auth.uid() = requester_id
    AND status = 'pending'
    AND public.user_is_active()
  );

-- Either party can update the status (accept/decline). Requester can
-- also withdraw by deleting the row.
CREATE POLICY "friendships_update_involved" ON public.friendships
  FOR UPDATE USING (
    (auth.uid() = requester_id OR auth.uid() = addressee_id)
    AND public.user_is_active()
  ) WITH CHECK (
    auth.uid() = requester_id OR auth.uid() = addressee_id
  );

CREATE POLICY "friendships_delete_involved" ON public.friendships
  FOR DELETE USING (
    auth.uid() = requester_id OR auth.uid() = addressee_id
  );


-- ---------------------------------------------------------------------
-- Trigger: keep updated_at fresh on UPDATE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_friendships_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_friendships_touch ON public.friendships;
CREATE TRIGGER trg_friendships_touch
  BEFORE UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.touch_friendships_updated_at();


-- ---------------------------------------------------------------------
-- Storage buckets for photo uploads
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('post_photos',  'post_photos',  TRUE, 1572864, ARRAY['image/jpeg','image/png','image/webp']),
  ('story_photos', 'story_photos', TRUE, 1572864, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;


-- Each bucket policy — only the file's owner can write/delete; anyone
-- authenticated can read (the buckets are public anyway).
DROP POLICY IF EXISTS "post_photos_insert_owner"  ON storage.objects;
DROP POLICY IF EXISTS "post_photos_update_owner"  ON storage.objects;
DROP POLICY IF EXISTS "post_photos_delete_owner"  ON storage.objects;
DROP POLICY IF EXISTS "story_photos_insert_owner" ON storage.objects;
DROP POLICY IF EXISTS "story_photos_update_owner" ON storage.objects;
DROP POLICY IF EXISTS "story_photos_delete_owner" ON storage.objects;

CREATE POLICY "post_photos_insert_owner" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'post_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "post_photos_update_owner" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'post_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "post_photos_delete_owner" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'post_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "story_photos_insert_owner" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'story_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "story_photos_update_owner" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'story_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "story_photos_delete_owner" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'story_photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );


-- =====================================================================
--  END OF PATCH 011
-- =====================================================================
