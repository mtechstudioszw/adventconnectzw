-- patch_133: let super-admins MANAGE Library content from the in-app admin
-- dashboard (add/edit hymns, upload music + EGW PDFs).
--
-- Before this, `hymns`, `library_items` and the `library` storage bucket had
-- READ-ONLY RLS (publish-gated SELECT) and content could only be added by hand
-- in the Supabase dashboard. This adds super-admin-gated write policies so the
-- founder can curate the Library from inside the app.

-- Reusable, RLS-safe super-admin predicate. SECURITY DEFINER so the policy can
-- read profiles.is_super_admin without tripping over profiles' own RLS, and so
-- it works from the storage schema too. Mirrors assert_super_admin() but
-- returns a boolean instead of raising.
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE(
    (SELECT is_super_admin FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

-- ---- hymns: super-admin full write (read stays publish-gated for everyone) --
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hymns TO authenticated;
DROP POLICY IF EXISTS hymns_admin_write ON public.hymns;
CREATE POLICY hymns_admin_write ON public.hymns
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- ---- library_items: super-admin full write ---------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.library_items TO authenticated;
DROP POLICY IF EXISTS library_items_admin_write ON public.library_items;
CREATE POLICY library_items_admin_write ON public.library_items
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- ---- library storage bucket: super-admin upload/replace/delete -------------
-- Public read already exists (library_objects_read). Allow EGW PDFs + music up
-- to 50 MB.
UPDATE storage.buckets SET file_size_limit = 52428800 WHERE id = 'library';

DROP POLICY IF EXISTS library_admin_insert ON storage.objects;
CREATE POLICY library_admin_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'library' AND public.is_super_admin());

DROP POLICY IF EXISTS library_admin_update ON storage.objects;
CREATE POLICY library_admin_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'library' AND public.is_super_admin())
  WITH CHECK (bucket_id = 'library' AND public.is_super_admin());

DROP POLICY IF EXISTS library_admin_delete ON storage.objects;
CREATE POLICY library_admin_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'library' AND public.is_super_admin());
