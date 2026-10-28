-- ============================================================================
--  patch_274 — one-way followers alongside friends; private profiles; links
--  STATUS: APPLIED to the live database 28 Oct 2026.
-- ============================================================================
--
--  Owner's redesign brief (28 Oct 2026), section 8: "Introduce a one-way
--  following system alongside the existing friend-request system."
--    * Friends stay exactly as they are (`friendships`, untouched).
--    * Following is one-way. Public profiles: a follow is active at once.
--      Private profiles: it waits as 'pending' until the person approves.
--    * Private profiles hide their posts from anyone who is not the author,
--      a friend, an approved follower or a super admin.
--    * No self-follow, no duplicate rows, nobody edits another member's
--      relationships. Blocked members can't follow.
--    * Counts and lists come through SECURITY DEFINER functions that apply
--      the privacy rule, so `follows` itself never needs to be readable by
--      strangers.
--  Also adds `profiles.website` (public link) for the new profile header.
--
--  CLAUDE.md checklist for profiles columns:
--    1. privilege trigger — `is_private` and `website` are member-editable
--       settings, not privileges, so the snap-back trigger must NOT revert
--       them; no change to profiles_block_privilege_self_grant().
--    2. explicit column grants added below (there is no table-level grant).
--    3. no column-level REVOKE is relied on.
--    4. the BEFORE trigger here covers INSERT only and returns
--       COALESCE(NEW, OLD).
-- ============================================================================

BEGIN;

-- Profile settings ------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_private boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS website    text;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_website_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_website_check
  CHECK (website IS NULL
         OR (length(website) <= 200 AND website ~* '^https?://[^\s]+$'));

GRANT SELECT (is_private, website) ON public.profiles TO authenticated;
GRANT UPDATE (is_private, website) ON public.profiles TO authenticated;

-- Follows ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follows (
  follower_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  followee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status      text NOT NULL DEFAULT 'active'
              CHECK (status IN ('active', 'pending')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);
CREATE INDEX IF NOT EXISTS follows_followee ON public.follows (followee_id, status);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

-- Only the two people involved can see their row directly.
DROP POLICY IF EXISTS follows_select_party ON public.follows;
CREATE POLICY follows_select_party ON public.follows FOR SELECT
  USING (follower_id = auth.uid() OR followee_id = auth.uid());

-- You can only create a follow FROM yourself, and not toward someone who
-- blocked you (or whom you blocked).
DROP POLICY IF EXISTS follows_insert_self ON public.follows;
CREATE POLICY follows_insert_self ON public.follows FOR INSERT
  WITH CHECK (follower_id = auth.uid()
              AND NOT public.is_blocked_by(followee_id)
              AND public.user_is_active());

-- Only the person being followed can approve a pending request.
DROP POLICY IF EXISTS follows_approve ON public.follows;
CREATE POLICY follows_approve ON public.follows FOR UPDATE
  USING (followee_id = auth.uid())
  WITH CHECK (followee_id = auth.uid() AND status = 'active');

-- Unfollow (follower) or remove / decline (followee).
DROP POLICY IF EXISTS follows_delete_party ON public.follows;
CREATE POLICY follows_delete_party ON public.follows FOR DELETE
  USING (follower_id = auth.uid() OR followee_id = auth.uid());

REVOKE ALL ON public.follows FROM anon;
GRANT SELECT, INSERT, DELETE ON public.follows TO authenticated;
GRANT UPDATE (status) ON public.follows TO authenticated;

-- The server decides the status, never the client.
CREATE OR REPLACE FUNCTION public.follows_set_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  NEW.status := CASE
    WHEN (SELECT is_private FROM public.profiles WHERE id = NEW.followee_id)
      THEN 'pending' ELSE 'active' END;
  NEW.created_at := now();
  RETURN COALESCE(NEW, OLD);
END;
$function$;
DROP TRIGGER IF EXISTS follows_set_status_trg ON public.follows;
CREATE TRIGGER follows_set_status_trg BEFORE INSERT ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.follows_set_status();

-- Notify: a new follower, a follow request, or a request approved.
CREATE OR REPLACE FUNCTION public.notify_follow()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
    VALUES (
      NEW.followee_id,
      CASE WHEN NEW.status = 'pending' THEN 'Follow request' ELSE 'New follower' END,
      public.notif_actor_name(NEW.follower_id) ||
        CASE WHEN NEW.status = 'pending' THEN ' asked to follow you.'
             ELSE ' started following you.' END,
      CASE WHEN NEW.status = 'pending' THEN 'follow_request' ELSE 'new_follower' END,
      NEW.follower_id::text,
      'user'
    );
  ELSIF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'active' THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
    VALUES (
      NEW.follower_id,
      'Follow request approved',
      public.notif_actor_name(NEW.followee_id) || ' approved your follow request.',
      'follow_approved',
      NEW.followee_id::text,
      'user'
    );
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;
DROP TRIGGER IF EXISTS follows_notify_trg ON public.follows;
CREATE TRIGGER follows_notify_trg AFTER INSERT OR UPDATE ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_follow();

-- Can the current user see [target]'s protected content?
CREATE OR REPLACE FUNCTION public.can_see_profile_content(target uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT
    target = auth.uid()
    OR public.is_super_admin()
    OR NOT COALESCE((SELECT is_private FROM public.profiles WHERE id = target), false)
    OR EXISTS (SELECT 1 FROM public.follows f
               WHERE f.follower_id = auth.uid() AND f.followee_id = target
                 AND f.status = 'active')
    OR EXISTS (SELECT 1 FROM public.friendships fr
               WHERE fr.status = 'accepted'
                 AND ((fr.requester_id = auth.uid() AND fr.addressee_id = target)
                   OR (fr.addressee_id = auth.uid() AND fr.requester_id = target)));
$function$;

-- Private profiles: their posts disappear for everyone else (RESTRICTIVE,
-- so it narrows the existing visibility policies rather than replacing them).
DROP POLICY IF EXISTS posts_private_profiles ON public.posts;
CREATE POLICY posts_private_profiles ON public.posts
  AS RESTRICTIVE FOR SELECT
  USING (public.can_see_profile_content(author_id));

-- Counts for any profile (counts are not protected content).
CREATE OR REPLACE FUNCTION public.profile_follow_stats(target uuid)
RETURNS TABLE (followers int, following int, i_follow text, follows_me boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT
    (SELECT count(*)::int FROM public.follows WHERE followee_id = target AND status = 'active'),
    (SELECT count(*)::int FROM public.follows WHERE follower_id = target AND status = 'active'),
    (SELECT status FROM public.follows WHERE follower_id = auth.uid() AND followee_id = target),
    EXISTS (SELECT 1 FROM public.follows
            WHERE follower_id = target AND followee_id = auth.uid() AND status = 'active');
$function$;

-- Lists, only when the viewer may see that profile's content.
CREATE OR REPLACE FUNCTION public.list_follows(target uuid, direction text)
RETURNS TABLE (user_id uuid, full_name text, username text,
               profile_photo_url text, is_verified boolean, followed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT p.id, p.full_name, p.username, p.profile_photo_url,
         (p.is_verified OR p.is_verified_admin), f.created_at
  FROM public.follows f
  JOIN public.profiles p
    ON p.id = CASE WHEN direction = 'followers' THEN f.follower_id ELSE f.followee_id END
  WHERE public.can_see_profile_content(target)
    AND f.status = 'active'
    AND CASE WHEN direction = 'followers' THEN f.followee_id ELSE f.follower_id END = target
    AND NOT public.is_blocked_by(p.id)
  ORDER BY f.created_at DESC
  LIMIT 500;
$function$;

-- Pending requests to ME (private-profile owners approve these).
CREATE OR REPLACE FUNCTION public.my_follow_requests()
RETURNS TABLE (user_id uuid, full_name text, username text,
               profile_photo_url text, requested_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT p.id, p.full_name, p.username, p.profile_photo_url, f.created_at
  FROM public.follows f JOIN public.profiles p ON p.id = f.follower_id
  WHERE f.followee_id = auth.uid() AND f.status = 'pending'
  ORDER BY f.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.can_see_profile_content(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.profile_follow_stats(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_follows(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.my_follow_requests() FROM PUBLIC;
-- anon too: posts_private_profiles is RESTRICTIVE, so it runs for
-- signed-out reads (the share-preview worker) and needs EXECUTE there.
GRANT EXECUTE ON FUNCTION public.can_see_profile_content(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.profile_follow_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_follows(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_follow_requests() TO authenticated;

COMMIT;

-- Checks:
--   * Follow a public profile → Followers count +1, they get "New follower".
--   * Make your profile private (Edit profile) → a new follow shows as
--     Requested; approve it from Followers → Requests.
--   * Someone not following a private profile sees no posts there.
