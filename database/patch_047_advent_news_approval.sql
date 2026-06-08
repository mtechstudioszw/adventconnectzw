-- =====================================================================
--  PATCH 047 — Advent News admin approval (tester bug #9)
--
--  Member-posted news must be reviewed before it goes live. Admin /
--  super-admin posts auto-approve. The public feed shows only
--  approved items; authors still see their own pending ones (so they
--  know it's "under review"); super admins see everything.
--
--  Rate limiting on posting news already exists (patch_036: 3/day).
--
--  Pieces:
--    1. advent_news.status ('pending'|'approved'|'rejected') +
--       rejection_reason. Existing rows backfilled to 'approved'.
--    2. BEFORE INSERT trigger forces member posts to 'pending',
--       admin posts to 'approved' — can't be spoofed from the client.
--    3. SELECT policy gates pending/rejected to author + admins.
--    4. admin_list_pending_news / admin_approve_news / admin_reject_news
--       RPCs (super-admin gated via assert_super_admin), each
--       notifying the author.
--
--  IDEMPOTENT.
-- =====================================================================

-- ----- 1. Columns ---------------------------------------------------
ALTER TABLE public.advent_news
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE public.advent_news
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Existing rows are already public — keep them visible.
UPDATE public.advent_news SET status = 'approved' WHERE status IS NULL
   OR status NOT IN ('pending','approved','rejected');

ALTER TABLE public.advent_news
  DROP CONSTRAINT IF EXISTS advent_news_status_check;
ALTER TABLE public.advent_news
  ADD CONSTRAINT advent_news_status_check
  CHECK (status IN ('pending','approved','rejected'));

-- ----- 2. Status-setting trigger ------------------------------------
CREATE OR REPLACE FUNCTION public.advent_news_set_status()
RETURNS TRIGGER AS $$
BEGIN
  IF (SELECT COALESCE(is_super_admin, FALSE)
        FROM public.profiles WHERE id = NEW.author_id) THEN
    NEW.status := 'approved';
  ELSE
    NEW.status := 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_advent_news_set_status ON public.advent_news;
CREATE TRIGGER trg_advent_news_set_status
  BEFORE INSERT ON public.advent_news
  FOR EACH ROW EXECUTE FUNCTION public.advent_news_set_status();

-- ----- 3. SELECT policy gates pending -------------------------------
DROP POLICY IF EXISTS advent_news_select_authenticated ON public.advent_news;
DROP POLICY IF EXISTS advent_news_select_visible ON public.advent_news;
CREATE POLICY advent_news_select_visible
  ON public.advent_news
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(status, 'approved') = 'approved'
    OR author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_super_admin = TRUE
    )
  );

-- ----- 4. Admin RPCs ------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_pending_news()
RETURNS TABLE (
  id BIGINT,
  title TEXT,
  summary TEXT,
  body TEXT,
  cover_photo_url TEXT,
  category TEXT,
  author_id UUID,
  author_name TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT n.id, n.title, n.summary, n.body, n.cover_photo_url, n.category,
           n.author_id,
           COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS author_name,
           n.created_at
      FROM public.advent_news n
      LEFT JOIN public.profiles p ON p.id = n.author_id
     WHERE n.status = 'pending'
     ORDER BY n.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_list_pending_news() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pending_news() TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_approve_news(p_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_author UUID;
  v_title TEXT;
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.advent_news
     SET status = 'approved', rejection_reason = NULL, published_at = NOW()
   WHERE id = p_id
  RETURNING author_id, title INTO v_author, v_title;

  IF v_author IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    ) VALUES (
      v_author,
      'Your news post is live',
      '"' || COALESCE(v_title, 'Your story') || '" was approved and is now on Advent News.',
      'news_approved', p_id::text, 'news'
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_approve_news(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_news(BIGINT) TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_reject_news(
  p_id BIGINT,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_author UUID;
  v_title TEXT;
  v_clean TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.advent_news
     SET status = 'rejected', rejection_reason = v_clean
   WHERE id = p_id
  RETURNING author_id, title INTO v_author, v_title;

  IF v_author IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    ) VALUES (
      v_author,
      'News post not approved',
      COALESCE(v_clean,
        '"' || COALESCE(v_title, 'Your story') || '" was not approved. Please review the guidelines and try again.'),
      'news_rejected', p_id::text, 'news'
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_reject_news(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_news(BIGINT, TEXT) TO authenticated;
