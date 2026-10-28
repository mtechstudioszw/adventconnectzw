-- ============================================================================
--  patch_273 — Save post and Hide post ("see less") for members
--  STATUS: APPLIED to the live database 28 Oct 2026.
-- ============================================================================
--
--  Owner's redesign brief (28 Oct 2026): "Saving must persist in a private
--  collection associated with the current account" and other people's posts
--  need "Hide post or see less". Neither exists: `saved_listings` is for
--  products only, and nothing records hidden posts.
--
--  Two private tables, one row per (member, post). Members can read, add
--  and remove only their own rows. A post's deletion removes its rows.
--  Hiding is personal: it only affects the member who hid it.
--
--  CLAUDE.md checklist: no `profiles` change; no triggers on shared tables;
--  grants are explicit and per-table.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.saved_posts (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id    uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS saved_posts_user_created
  ON public.saved_posts (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.hidden_posts (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id    uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

ALTER TABLE public.saved_posts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hidden_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS saved_posts_own ON public.saved_posts;
CREATE POLICY saved_posts_own ON public.saved_posts
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS hidden_posts_own ON public.hidden_posts;
CREATE POLICY hidden_posts_own ON public.hidden_posts
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

REVOKE ALL ON public.saved_posts, public.hidden_posts FROM anon;
GRANT SELECT, INSERT, DELETE ON public.saved_posts  TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.hidden_posts TO authenticated;

COMMIT;

-- Check (in the app): ⋯ on a post → Save → Profile → ⋯ → Saved shows it;
-- ⋯ → Hide post → it leaves your feed and stays gone after a refresh.
