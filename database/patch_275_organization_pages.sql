-- ============================================================================
--  patch_275 — organization Pages (ministries, schools, community, business)
--  STATUS: DRAFT, NOT YET RUN. Owner to run in the SQL editor AFTER 274.
-- ============================================================================
--
--  Owner's redesign brief (28 Oct 2026), section 9.
--
--  CHURCHES ARE DELIBERATELY NOT MOVED HERE. They keep `churches`,
--  `church_admins` (appointment-letter verification) and
--  `church_followers` exactly as they are. Moving 2,600+ church rows and
--  their verified admins is the "silent migration" the brief forbids, and
--  the brief also says not to remove the existing verification until a
--  replacement is ready. So a church Page IS the existing church page, and
--  the `pages` table refuses category 'church' — nobody can create a fake
--  church Page to get around church-admin approval.
--
--  Rules enforced here, not in the app:
--    * Anyone active can create up to 3 Pages; the creator becomes owner.
--    * Only owners/editors edit a Page; only owners manage admins; the last
--      owner can't be removed.
--    * `is_verified` and `status` are set only by the super admin (guard
--      trigger snaps them back for everyone else). Paying never verifies.
--    * Hidden Pages (status = 'hidden') disappear for everyone but their
--      admins and the super admin.
--    * Posting AS a Page (posts.page_id) needs an owner/editor of it —
--      same pattern as patch_141 for churches.
--    * Followers are counted, never listed publicly.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.pages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 80),
  category      text NOT NULL
                CHECK (category IN ('ministry', 'school', 'community', 'business')),
  description   text CHECK (description IS NULL OR length(description) <= 1500),
  logo_url      text,
  cover_url     text,
  city          text CHECK (city IS NULL OR length(city) <= 80),
  country       text CHECK (country IS NULL OR country ~ '^[A-Z]{2}$'),
  service_area  text CHECK (service_area IS NULL OR length(service_area) <= 120),
  contact_email text CHECK (contact_email IS NULL
                            OR (length(contact_email) <= 120
                                AND contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  contact_phone text CHECK (contact_phone IS NULL
                            OR contact_phone ~ '^\+?[0-9 ()-]{6,20}$'),
  website       text CHECK (website IS NULL
                            OR (length(website) <= 200 AND website ~* '^https?://[^\s]+$')),
  is_verified   boolean NOT NULL DEFAULT false,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'hidden')),
  moderation_reason text,
  created_by    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pages_category ON public.pages (category, status);
CREATE INDEX IF NOT EXISTS pages_name_lower ON public.pages (lower(name));

CREATE TABLE IF NOT EXISTS public.page_admins (
  page_id    uuid NOT NULL REFERENCES public.pages(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role       text NOT NULL DEFAULT 'editor' CHECK (role IN ('owner', 'editor')),
  added_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (page_id, user_id)
);
CREATE INDEX IF NOT EXISTS page_admins_user ON public.page_admins (user_id);

CREATE TABLE IF NOT EXISTS public.page_follows (
  page_id    uuid NOT NULL REFERENCES public.pages(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (page_id, user_id)
);

-- Helpers -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.page_role(p_page uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT role FROM public.page_admins
   WHERE page_id = p_page AND user_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.can_edit_page(p_page uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT public.is_super_admin() OR public.page_role(p_page) IS NOT NULL;
$function$;

-- RLS: pages ------------------------------------------------------------------
ALTER TABLE public.pages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pages_select ON public.pages;
CREATE POLICY pages_select ON public.pages FOR SELECT
  USING (status = 'active' OR public.can_edit_page(id));

DROP POLICY IF EXISTS pages_insert ON public.pages;
CREATE POLICY pages_insert ON public.pages FOR INSERT
  WITH CHECK (created_by = auth.uid() AND public.user_is_active());

DROP POLICY IF EXISTS pages_update ON public.pages;
CREATE POLICY pages_update ON public.pages FOR UPDATE
  USING (public.can_edit_page(id))
  WITH CHECK (public.can_edit_page(id));

-- Only an owner (or the super admin) deletes a Page.
DROP POLICY IF EXISTS pages_delete ON public.pages;
CREATE POLICY pages_delete ON public.pages FOR DELETE
  USING (public.is_super_admin() OR public.page_role(id) = 'owner');

REVOKE ALL ON public.pages FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pages TO authenticated;

-- Guard: verification, status, ownership and timestamps are not the
-- client's to set. Snaps them back for anyone but the super admin.
CREATE OR REPLACE FUNCTION public.pages_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_super_admin() THEN
      NEW.is_verified := false;
      NEW.status := 'active';
      NEW.moderation_reason := NULL;
      NEW.created_by := auth.uid();
      SELECT count(*) INTO v_count FROM public.pages WHERE created_by = auth.uid();
      IF v_count >= 3 THEN
        RAISE EXCEPTION 'PAGE_LIMIT'
          USING ERRCODE = '42501',
                HINT = 'You can create up to 3 Pages.';
      END IF;
    END IF;
    NEW.created_at := now();
  ELSE
    IF auth.uid() IS NOT NULL AND NOT public.is_super_admin() THEN
      NEW.is_verified := OLD.is_verified;
      NEW.status := OLD.status;
      NEW.moderation_reason := OLD.moderation_reason;
    END IF;
    NEW.created_by := OLD.created_by;
    NEW.created_at := OLD.created_at;
  END IF;
  NEW.updated_at := now();
  RETURN COALESCE(NEW, OLD);
END;
$function$;
DROP TRIGGER IF EXISTS pages_guard_trg ON public.pages;
CREATE TRIGGER pages_guard_trg BEFORE INSERT OR UPDATE ON public.pages
  FOR EACH ROW EXECUTE FUNCTION public.pages_guard();

-- The creator becomes the first owner.
CREATE OR REPLACE FUNCTION public.pages_add_owner()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.page_admins (page_id, user_id, role, added_by)
  VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by)
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS pages_add_owner_trg ON public.pages;
CREATE TRIGGER pages_add_owner_trg AFTER INSERT ON public.pages
  FOR EACH ROW EXECUTE FUNCTION public.pages_add_owner();

-- RLS: page_admins --------------------------------------------------------------
-- Readable by the Page's own admins (and the super admin). Writes go
-- through the RPCs below, never directly.
ALTER TABLE public.page_admins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS page_admins_select ON public.page_admins;
CREATE POLICY page_admins_select ON public.page_admins FOR SELECT
  USING (user_id = auth.uid() OR public.can_edit_page(page_id));
REVOKE ALL ON public.page_admins FROM anon, authenticated;
GRANT SELECT ON public.page_admins TO authenticated;

-- RLS: page_follows ----------------------------------------------------------------
ALTER TABLE public.page_follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS page_follows_select_own ON public.page_follows;
CREATE POLICY page_follows_select_own ON public.page_follows FOR SELECT
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS page_follows_insert_own ON public.page_follows;
CREATE POLICY page_follows_insert_own ON public.page_follows FOR INSERT
  WITH CHECK (user_id = auth.uid() AND public.user_is_active()
              AND EXISTS (SELECT 1 FROM public.pages p
                          WHERE p.id = page_id AND p.status = 'active'));
DROP POLICY IF EXISTS page_follows_delete_own ON public.page_follows;
CREATE POLICY page_follows_delete_own ON public.page_follows FOR DELETE
  USING (user_id = auth.uid());
REVOKE ALL ON public.page_follows FROM anon;
GRANT SELECT, INSERT, DELETE ON public.page_follows TO authenticated;

-- Admin management RPCs ----------------------------------------------------------
-- Add by @username so nobody needs another member's id. Owners only.
CREATE OR REPLACE FUNCTION public.add_page_admin(p_page uuid, p_username text, p_role text DEFAULT 'editor')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid;
  v_name text;
BEGIN
  IF NOT (public.is_super_admin() OR public.page_role(p_page) = 'owner') THEN
    RAISE EXCEPTION 'Only a Page owner can add admins.' USING ERRCODE = '42501';
  END IF;
  IF p_role NOT IN ('owner', 'editor') THEN
    RAISE EXCEPTION 'Unknown role.' USING ERRCODE = '22023';
  END IF;
  SELECT id INTO v_user FROM public.profiles
   WHERE lower(username) = lower(ltrim(btrim(p_username), '@'));
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'NO_SUCH_USER' USING ERRCODE = 'P0002',
      HINT = 'No member has that username.';
  END IF;
  -- Re-adding an existing owner as an editor is a demotion; never let it
  -- leave the Page without an owner.
  IF p_role = 'editor'
     AND EXISTS (SELECT 1 FROM public.page_admins
                 WHERE page_id = p_page AND user_id = v_user AND role = 'owner')
     AND (SELECT count(*) FROM public.page_admins
          WHERE page_id = p_page AND role = 'owner') <= 1 THEN
    RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = '42501',
      HINT = 'A Page needs at least one owner. Add another owner first.';
  END IF;
  INSERT INTO public.page_admins (page_id, user_id, role, added_by)
  VALUES (p_page, v_user, p_role, auth.uid())
  ON CONFLICT (page_id, user_id) DO UPDATE SET role = EXCLUDED.role;

  SELECT name INTO v_name FROM public.pages WHERE id = p_page;
  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (v_user, 'Page admin',
          public.notif_actor_name(auth.uid()) || ' made you ' ||
            CASE WHEN p_role = 'owner' THEN 'an owner' ELSE 'an editor' END ||
            ' of ' || v_name || '.',
          'page_admin_added', p_page::text, 'page');
  RETURN v_user;
END;
$function$;

-- Remove an admin (owners), or step down yourself. Never the last owner.
CREATE OR REPLACE FUNCTION public.remove_page_admin(p_page uuid, p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
BEGIN
  IF NOT (public.is_super_admin() OR public.page_role(p_page) = 'owner'
          OR p_user = auth.uid()) THEN
    RAISE EXCEPTION 'Only a Page owner can remove admins.' USING ERRCODE = '42501';
  END IF;
  SELECT role INTO v_role FROM public.page_admins
   WHERE page_id = p_page AND user_id = p_user;
  IF v_role = 'owner' AND (SELECT count(*) FROM public.page_admins
                           WHERE page_id = p_page AND role = 'owner') <= 1 THEN
    RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = '42501',
      HINT = 'A Page needs at least one owner. Add another owner first.';
  END IF;
  DELETE FROM public.page_admins WHERE page_id = p_page AND user_id = p_user;
END;
$function$;

-- The admin list with names, for the Page's own admins.
CREATE OR REPLACE FUNCTION public.list_page_admins(p_page uuid)
RETURNS TABLE (user_id uuid, full_name text, username text,
               profile_photo_url text, role text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT pr.id, pr.full_name, pr.username, pr.profile_photo_url, pa.role
  FROM public.page_admins pa JOIN public.profiles pr ON pr.id = pa.user_id
  WHERE pa.page_id = p_page AND public.can_edit_page(p_page)
  ORDER BY (pa.role = 'owner') DESC, pa.created_at;
$function$;

-- Follower count + whether I follow + my role, in one call.
CREATE OR REPLACE FUNCTION public.page_stats(p_page uuid)
RETURNS TABLE (followers int, i_follow boolean, my_role text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT
    (SELECT count(*)::int FROM public.page_follows WHERE page_id = p_page),
    EXISTS (SELECT 1 FROM public.page_follows
            WHERE page_id = p_page AND user_id = auth.uid()),
    public.page_role(p_page);
$function$;

-- Super admin: verify / hide a Page, with a notice to its owners.
CREATE OR REPLACE FUNCTION public.admin_set_page_state(
  p_page uuid, p_verified boolean, p_hidden boolean, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_name text;
  v_was_hidden boolean;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Super admin only.' USING ERRCODE = '42501';
  END IF;
  SELECT name, status = 'hidden' INTO v_name, v_was_hidden
    FROM public.pages WHERE id = p_page;
  UPDATE public.pages
     SET is_verified = p_verified,
         status = CASE WHEN p_hidden THEN 'hidden' ELSE 'active' END,
         moderation_reason = CASE WHEN p_hidden THEN p_reason ELSE NULL END
   WHERE id = p_page;
  IF p_hidden AND NOT COALESCE(v_was_hidden, false) THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
    SELECT pa.user_id, 'Page hidden',
           v_name || ' was hidden by the moderators' ||
             COALESCE(': ' || NULLIF(btrim(p_reason), ''), '.') ||
             ' If you believe this is a mistake you can appeal.',
           'page_hidden', p_page::text, 'page'
      FROM public.page_admins pa
     WHERE pa.page_id = p_page AND pa.role = 'owner';
  END IF;
END;
$function$;

-- Posting as a Page --------------------------------------------------------------
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS page_id uuid REFERENCES public.pages(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS posts_page ON public.posts (page_id, created_at DESC)
  WHERE page_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.posts_validate_page()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.page_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.page_id IS DISTINCT FROM OLD.page_id) THEN
    IF NOT public.can_edit_page(NEW.page_id) THEN
      RAISE EXCEPTION 'Only an admin of this Page can post as the Page.'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.church_id IS NOT NULL THEN
      RAISE EXCEPTION 'A post belongs to a church or a Page, not both.'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;
-- A hidden Page's posts disappear with it (RESTRICTIVE: narrows the
-- existing post visibility rules, never widens them).
CREATE OR REPLACE FUNCTION public.page_is_visible(p_page uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT p_page IS NULL
      OR EXISTS (SELECT 1 FROM public.pages WHERE id = p_page AND status = 'active')
      OR public.can_edit_page(p_page);
$function$;
REVOKE ALL ON FUNCTION public.page_is_visible(uuid) FROM PUBLIC;
-- anon too: a RESTRICTIVE policy runs for signed-out reads (e.g. the
-- share-preview worker), and without EXECUTE every such read would error.
GRANT EXECUTE ON FUNCTION public.page_is_visible(uuid) TO authenticated, anon;

DROP POLICY IF EXISTS posts_hidden_pages ON public.posts;
CREATE POLICY posts_hidden_pages ON public.posts
  AS RESTRICTIVE FOR SELECT
  USING (public.page_is_visible(page_id));

DROP TRIGGER IF EXISTS trg_posts_validate_page ON public.posts;
CREATE TRIGGER trg_posts_validate_page BEFORE INSERT OR UPDATE OF page_id ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.posts_validate_page();

-- Notify a Page's owners of new followers.
CREATE OR REPLACE FUNCTION public.notify_page_follow()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  SELECT pa.user_id, 'New Page follower',
         public.notif_actor_name(NEW.user_id) || ' followed ' || p.name || '.',
         'page_follower', NEW.page_id::text, 'page'
    FROM public.page_admins pa JOIN public.pages p ON p.id = pa.page_id
   WHERE pa.page_id = NEW.page_id AND pa.role = 'owner'
     AND pa.user_id <> NEW.user_id;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS page_follows_notify_trg ON public.page_follows;
CREATE TRIGGER page_follows_notify_trg AFTER INSERT ON public.page_follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_page_follow();

REVOKE ALL ON FUNCTION public.page_role(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_edit_page(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_page_admin(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_page_admin(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_page_admins(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.page_stats(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_page_state(uuid, boolean, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.page_role(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.can_edit_page(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.add_page_admin(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_page_admin(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_page_admins(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.page_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_page_state(uuid, boolean, boolean, text) TO authenticated;

COMMIT;

-- Checks:
--   * Profile → ⋯ → Pages → Create: the Page opens with you as owner.
--   * A 4th Page is refused ("You can create up to 3 Pages").
--   * Editing is_verified from the app does nothing (guard trigger).
--   * Post as the Page from its screen: the post shows the Page name.
--   * Someone else can follow it; the owner gets "New Page follower".
