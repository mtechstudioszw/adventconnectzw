-- =====================================================================
--  PATCH 082 — notify the story author when someone likes their story
--
--  "User A liked your story" → an in-app notification (type 'social')
--  for the story's author. Skips self-likes.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_story_like()
RETURNS TRIGGER AS $$
DECLARE
  v_author UUID;
  v_liker  TEXT;
BEGIN
  SELECT author_id INTO v_author FROM public.stories WHERE id = NEW.story_id;
  IF v_author IS NULL OR v_author = NEW.user_id THEN
    RETURN NEW;
  END IF;
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone') INTO v_liker
    FROM public.profiles WHERE id = NEW.user_id;
  INSERT INTO public.notifications
    (user_id, type, title, body, reference_id, reference_type)
  VALUES (
    v_author, 'social', 'New story like',
    v_liker || ' liked your story',
    NEW.story_id::text, 'story'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_notify_story_like ON public.story_likes;
CREATE TRIGGER trg_notify_story_like
  AFTER INSERT ON public.story_likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_story_like();
