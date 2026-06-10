-- =====================================================================
--  PATCH 073 — storage purge helpers (called by the purge-storage edge fn)
--
--  Story photos for expired stories, and chat media/voice notes whose
--  message row is gone (hard-deleted) or soft-deleted, are never removed
--  from the bucket. SQL can't free the S3 file (must go through the
--  storage API), so the edge function asks this RPC for the orphaned
--  object names and removes them via storage.remove().
-- =====================================================================

-- Names (paths) of objects to purge for a bucket.
--   story_photos: anything older than 48h (stories expire at 24h).
--   chat_media / voice_notes: objects not referenced by any live
--     (non-deleted) message's media_url.
CREATE OR REPLACE FUNCTION public.purgeable_storage_names(p_bucket TEXT)
RETURNS TABLE (name TEXT) AS $$
  SELECT o.name
    FROM storage.objects o
   WHERE o.bucket_id = p_bucket
     AND (
       (p_bucket = 'story_photos' AND o.created_at < now() - INTERVAL '48 hours')
       OR (
         p_bucket IN ('chat_media', 'voice_notes')
         AND o.created_at < now() - INTERVAL '24 hours'
         AND NOT EXISTS (
           SELECT 1 FROM public.messages m
            WHERE m.media_url = o.name AND m.is_deleted = FALSE
         )
       )
     )
   LIMIT 500;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, storage;
GRANT EXECUTE ON FUNCTION public.purgeable_storage_names(TEXT) TO service_role;
