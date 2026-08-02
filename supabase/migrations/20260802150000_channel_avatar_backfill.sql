-- YouTube channel rows showing the wrong avatar.
--
-- Founder report, 2 Aug 2026. The cause is not the YouTube API and not
-- the quota: every row in `youtube_channels` already holds a correct
-- `thumbnail_url` (all 17 of them, checked). The problem is that the
-- video card reads `youtube_videos.channel_thumb_url` — a denormalised
-- snapshot taken when the video was ingested — and 749 of 40,328 video
-- rows have it NULL. The card then falls back to a generic TV glyph,
-- which is the "wrong avatar" a member sees.
--
-- Deliberately NOT fixed by fetching anything. `brief03-open-bugs`
-- documents a self-healing quota hole with three cron jobs behind it;
-- the data needed here is already in the database, so this migration
-- spends no API units at all.
--
-- Three parts: backfill what is missing, keep new inserts filled, and
-- propagate a channel that changes its picture.

-- 1. Backfill. Only touches rows that actually disagree.
UPDATE public.youtube_videos v
   SET channel_thumb_url = c.thumbnail_url
  FROM public.youtube_channels c
 WHERE c.channel_id = v.channel_id
   AND v.channel_thumb_url IS DISTINCT FROM c.thumbnail_url
   AND c.thumbnail_url IS NOT NULL;

-- 2. New videos inherit the channel's avatar when the ingest didn't
--    supply one. BEFORE INSERT OR UPDATE so a re-ingest that drops the
--    field doesn't blank an avatar that was already right.
CREATE OR REPLACE FUNCTION public.fill_video_channel_thumb()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.channel_thumb_url IS NULL AND NEW.channel_id IS NOT NULL THEN
    SELECT thumbnail_url INTO NEW.channel_thumb_url
      FROM public.youtube_channels
     WHERE channel_id = NEW.channel_id;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_fill_video_channel_thumb ON public.youtube_videos;
CREATE TRIGGER trg_fill_video_channel_thumb
  BEFORE INSERT OR UPDATE ON public.youtube_videos
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_video_channel_thumb();

-- 3. A channel that rebrands drags its back catalogue along, so the
--    snapshot can never drift again. Guarded on an actual change —
--    without the WHEN, every no-op channel refresh would rewrite tens of
--    thousands of video rows.
CREATE OR REPLACE FUNCTION public.propagate_channel_thumb()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.youtube_videos
     SET channel_thumb_url = NEW.thumbnail_url
   WHERE channel_id = NEW.channel_id
     AND channel_thumb_url IS DISTINCT FROM NEW.thumbnail_url;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_propagate_channel_thumb ON public.youtube_channels;
CREATE TRIGGER trg_propagate_channel_thumb
  AFTER UPDATE OF thumbnail_url ON public.youtube_channels
  FOR EACH ROW
  WHEN (OLD.thumbnail_url IS DISTINCT FROM NEW.thumbnail_url
        AND NEW.thumbnail_url IS NOT NULL)
  EXECUTE FUNCTION public.propagate_channel_thumb();
