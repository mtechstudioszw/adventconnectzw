-- patch_141: church-branded feed posts. A church admin can post an update to
-- the GENERAL home feed on behalf of their church — it shows with the church's
-- name + gold tick so all users (members or not) learn about the church.
--
-- author_id stays the admin (for moderation/ownership); church_id is the
-- attribution. A trigger guarantees only an approved admin of that church (or
-- the super admin) can set church_id, so nobody can fake a church post.

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS church_id bigint
  REFERENCES public.churches(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.posts_validate_church()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.church_id IS NOT NULL THEN
    IF NOT (
      public.is_super_admin()
      OR EXISTS (
        SELECT 1 FROM public.church_admins ca
         WHERE ca.church_id = NEW.church_id
           AND ca.user_id = auth.uid()
           AND ca.status = 'approved'
      )
    ) THEN
      RAISE EXCEPTION 'Only an approved admin of this church can post as the church.'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_posts_validate_church ON public.posts;
CREATE TRIGGER trg_posts_validate_church
  BEFORE INSERT OR UPDATE OF church_id ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.posts_validate_church();
