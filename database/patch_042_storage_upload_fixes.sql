-- =====================================================================
--  PATCH 042 — Storage upload fixes (tester bugs #2 + #3)
--
--  #2 Event flyer upload fails for everyone except the super admin:
--     event_flyers INSERT was only permitted by
--     storage_church_event_super_admin_write (is_super_admin = true).
--     The own-folder INSERT policy (storage_own_folder_write) only
--     listed profile_photos + product_photos, NOT event_flyers. So a
--     normal user posting an event could not upload its flyer.
--     FIX: add an own-folder INSERT policy for event_flyers so any
--     authenticated user can upload a flyer into their own folder
--     ({uid}/file). The super-admin policy still applies too.
--
--  #3 Profile photo upload works for some users, not others:
--     Not an RLS issue — the path is {uid}/ts.ext which satisfies the
--     own-folder check. The cause is the bucket file_size_limit:
--     profile_photos was 800 KB, event_flyers 600 KB, church_photos
--     500 KB. A normal phone photo (even after the app's compression)
--     often exceeds those, so it failed for users with larger images
--     and "worked fine" for users with small ones.
--     FIX: raise image bucket limits to 5 MB (matches the app's
--     intended image ceiling). The client still compresses before
--     upload; this just stops the hard server rejection.
--
--  IDEMPOTENT: DROP POLICY IF EXISTS before CREATE; UPDATE is safe to
--  re-run.
-- =====================================================================

-- ----- #2: allow authenticated users to upload their own event flyer
DROP POLICY IF EXISTS "event_flyers_insert_owner" ON storage.objects;
CREATE POLICY "event_flyers_insert_owner"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'event_flyers'
    AND (auth.uid())::text = (storage.foldername(name))[1]
  );

-- ----- #3 (+ #2 size): raise image bucket size limits to 5 MB -------
UPDATE storage.buckets
   SET file_size_limit = 5242880   -- 5 MB
 WHERE id IN (
   'profile_photos',
   'event_flyers',
   'church_photos',
   'product_photos',
   'post_photos',
   'story_photos'
 );
