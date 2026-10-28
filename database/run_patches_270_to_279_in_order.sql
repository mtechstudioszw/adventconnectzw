-- Patches 276, 270–275, 277, 278, 279 in the order they must run.
-- Paste ALL of this into Supabase → SQL Editor → New query → Run.
-- Each patch commits on its own; if one errors, the ones before it stay
-- applied and the rest do not run. Send the error message to Claude.

-- ======================== patch_276_seller_privilege_guard.sql ========================
-- ============================================================================
--  patch_276 — sellers/products: members can't grant themselves privileges
--  STATUS: DRAFT, NOT YET RUN. **SECURITY — run this first, before 270–275.**
-- ============================================================================
--
--  Found 28 Oct 2026 while building marketplace ranking. `authenticated`
--  holds UPDATE/INSERT on EVERY column of `sellers` and `products`, and the
--  only policy is "it's your own row". Nothing snapped privileged columns
--  back, so any member with a store could, straight from the API:
--    * set sellers.status = 'approved' (skip review, or undo a rejection
--      or ban), verified / sda_verified = true (the gold tick),
--      featured = true, rating = 5 with any rating_count;
--    * set products.is_featured = true and any view_count.
--  The same class of hole as patch_188 (self-granted verified tick).
--  Checked the live data on 28 Oct: no store shows signs of having used it
--  (every approved store has approved_at from the admin function, every
--  rating matches its real reviews, nothing verified or featured).
--
--  The guard lets every LEGITIMATE path through unchanged:
--    * super admins and server-side work (no JWT) — admin_approve_seller,
--      admin_reject_seller, the admin web tools;
--    * seller_reapply (runs as the seller): the one status change a seller
--      may make is exactly that step — rejected → pending (or
--      final_review_pending on the 3rd attempt), attempts + 1, store
--      inactive — which is no more than the RPC already allows;
--    * recompute_seller_rating (runs as the buyer who rated): rating and
--      rating_count are RECOMPUTED here from seller_ratings, so the real
--      numbers always pass and invented ones never do.
--
--  CLAUDE.md: BEFORE triggers return COALESCE(NEW, OLD).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sellers_guard_privileged()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_reapply boolean;
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.verified := false;
    NEW.sda_verified := false;
    NEW.featured := false;
    NEW.rating := 0;
    NEW.rating_count := 0;
    NEW.approved_at := NULL;
    NEW.rejection_reason := NULL;
    NEW.application_attempts := 1;
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Exactly the seller_reapply transition, nothing else.
  v_reapply :=
        OLD.status = 'rejected'
    AND NEW.application_attempts = COALESCE(OLD.application_attempts, 1) + 1
    AND NEW.application_attempts <= 3
    AND NEW.status = CASE WHEN NEW.application_attempts >= 3
                          THEN 'final_review_pending' ELSE 'pending' END
    AND NEW.is_active = false;

  IF NOT v_reapply THEN
    NEW.status := OLD.status;
    NEW.application_attempts := OLD.application_attempts;
    NEW.rejection_reason := OLD.rejection_reason;
    NEW.is_active := OLD.is_active;
  END IF;

  NEW.verified := OLD.verified;
  NEW.sda_verified := OLD.sda_verified;
  NEW.featured := OLD.featured;
  NEW.approved_at := OLD.approved_at;

  -- Always the truth from seller_ratings, whoever is writing.
  SELECT count(*), COALESCE(avg(r.rating)::decimal(3,2), 0)
    INTO NEW.rating_count, NEW.rating
    FROM public.seller_ratings r
   WHERE r.seller_id = OLD.id;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS sellers_guard_privileged_trg ON public.sellers;
CREATE TRIGGER sellers_guard_privileged_trg
  BEFORE INSERT OR UPDATE ON public.sellers
  FOR EACH ROW EXECUTE FUNCTION public.sellers_guard_privileged();

CREATE OR REPLACE FUNCTION public.products_guard_privileged()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.is_featured := false;
    NEW.view_count := 0;
  ELSE
    NEW.is_featured := OLD.is_featured;
    -- record_product_view (patch_277) is the one writer allowed to move
    -- view_count; it marks its own transaction.
    IF COALESCE(current_setting('app.recording_view', true), '') <> 'on' THEN
      NEW.view_count := OLD.view_count;
    END IF;
    NEW.seller_id := OLD.seller_id;
    NEW.created_at := OLD.created_at;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS products_guard_privileged_trg ON public.products;
CREATE TRIGGER products_guard_privileged_trg
  BEFORE INSERT OR UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.products_guard_privileged();

COMMIT;

-- Checks (as an ordinary seller, from the app or the API):
--   * PATCH sellers set verified=true / featured=true / status='approved'
--     → succeeds but the values don't change.
--   * Rate a store from another account → its rating still updates.
--   * Reapply after a rejection → goes to pending as before.
--   * Super admin approve/reject → works as before.

-- ======================== patch_270_order_status_transitions.sql ========================
-- ============================================================================
--  patch_270 — order status transitions are enforced server-side
--  STATUS: DRAFT, NOT YET RUN. Owner to review, then run in the SQL editor.
-- ============================================================================
--
--  Found 28 Oct 2026 (Batch 2 Marketplace audit), read from the live DB:
--  `orders_update_party` lets EITHER party update the row, and the only
--  trigger guard (`orders_freeze_financials`) protects money columns, not
--  `status`. So through the API, not the app:
--    * a buyer can set their own order to 'confirmed' or 'completed' —
--      i.e. fake the seller's acceptance;
--    * either party can reopen a 'cancelled' or 'completed' order.
--  The app's buttons never offer these, but RLS is the real boundary.
--
--  Allowed after this patch (matches exactly what the app's buttons do):
--    seller: pending   -> confirmed | cancelled
--            confirmed -> completed | cancelled
--    buyer : pending   -> cancelled
--            confirmed -> cancelled
--    nobody: anything out of 'completed' or 'cancelled'
--  An UPDATE that leaves status unchanged (e.g. editing the note) passes.
--  service_role / SQL editor (auth.uid() IS NULL) is not restricted, so
--  admins can still repair data.
--
--  CLAUDE.md checklist: BEFORE UPDATE only (no DELETE), so NEW is never
--  NULL here; returns COALESCE(NEW, OLD) anyway to keep the house rule.
--  No new columns, no grants needed.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.orders_guard_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR uid IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF OLD.status IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'order % is % and can no longer change', OLD.id, OLD.status
      USING ERRCODE = '42501';
  END IF;

  IF uid = OLD.seller_id THEN
    IF (OLD.status = 'pending'   AND NEW.status IN ('confirmed', 'cancelled'))
    OR (OLD.status = 'confirmed' AND NEW.status IN ('completed', 'cancelled')) THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  ELSIF uid = OLD.buyer_id THEN
    IF OLD.status IN ('pending', 'confirmed') AND NEW.status = 'cancelled' THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  END IF;

  RAISE EXCEPTION 'order status % -> % is not allowed for this user',
    OLD.status, NEW.status
    USING ERRCODE = '42501';
END;
$function$;

DROP TRIGGER IF EXISTS orders_guard_status_transition_trg ON public.orders;
CREATE TRIGGER orders_guard_status_transition_trg
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.orders_guard_status_transition();

-- Verify (run as yourself in the app, or with a test buyer JWT):
--   buyer:  update orders set status='confirmed' where id=<their order>;
--           -> ERROR 42501 ... is not allowed for this user
--   seller: update orders set status='confirmed' where id=<pending order>;
--           -> UPDATE 1

-- ======================== patch_271_music_titles_cleanup.sql ========================
-- ============================================================================
--  patch_271 — readable titles for the uploaded music tracks
--  STATUS: DRAFT, NOT YET RUN. Owner to review, then run in the SQL editor.
-- ============================================================================
--
--  Seen on the founder's phone, 28 Oct 2026: the Music shelf shows raw file
--  names ("Love_at_Home_-_SDA_Hymn_#_652(0)"). Bulk upload used the file
--  name as the title; the uploader now cleans it (lib/utils/upload_title.dart),
--  but the 11 rows already uploaded need fixing by hand.
--
--  Ids and current titles read from the live DB (read-only) on 28 Oct 2026.
--  Each UPDATE matches on id AND the current title, so a row someone has
--  already renamed is left alone.
--
--  Not decided here (owner): id 102 and id 108 are the same hymn
--  ("Joy By and By", #430). Unpublish one with the commented line below.
-- ============================================================================

BEGIN;

UPDATE public.library_items SET title = 'Love at Home (SDA Hymnal 652)'
 WHERE id = 110 AND title = 'Love_at_Home_-_SDA_Hymn_#_652(0)';
UPDATE public.library_items SET title = 'Live Out Thy Life Within Me (SDA Hymnal 316)'
 WHERE id = 109 AND title = 'Live_Out_Thy_Life_Within_Me_-_SDA_Hymn_#_316(0)(1)';
UPDATE public.library_items SET title = 'Joy By and By (SDA Hymnal 430) — Breath of Praise'
 WHERE id = 108 AND title = 'Joy_By_and_By____SDA_HYMN_#430____Breath_of_Praise(256k)';
UPDATE public.library_items SET title = 'In a Little While We''re Going Home (SDA Hymnal 626)'
 WHERE id = 107 AND title = 'In_a_Little_While_We_re_Going_Home___SDA_hymn_#_626(0)';
UPDATE public.library_items SET title = 'I Will Sing of Jesus'' Love (SDA Hymnal 183)'
 WHERE id = 106 AND title = 'I_will_sing_of_Jesus_Love_SDA_Hymn_#_183(0)';
UPDATE public.library_items SET title = 'Holy, Holy, Holy (SDA Hymnal 73)'
 WHERE id = 105 AND title = 'Holy,_Holy,_Holy_-_SDA_Hymn_#_73(0)';
UPDATE public.library_items SET title = 'All the Way (SDA Hymnal 516)'
 WHERE id = 104 AND title = 'All_the_way_SDA_Hymn_#_516(0)';
UPDATE public.library_items SET title = 'A Shelter in the Time of Storm (SDA Hymnal 528)'
 WHERE id = 103 AND title = 'A_Shelter_in_the_Time_of_Storm___SDA_Hymn_#_528(0)';
UPDATE public.library_items SET title = 'Joy By and By (SDA Hymnal 430)'
 WHERE id = 102 AND title = 'Joy_By_and_By____SDA_HYMN_#430';
UPDATE public.library_items SET title = 'Come, Thou Fount'
 WHERE id = 101 AND title = 'Come_Thou_Fount Song';
UPDATE public.library_items SET title = 'Jesus, Keep Me Near the Cross'
 WHERE id = 99 AND title = 'Jesus Keep Me Near The Cross Song';

-- Duplicate (owner's choice — uncomment to hide the plain copy):
-- UPDATE public.library_items SET is_published = false WHERE id = 102;

COMMIT;

-- Check:
--   SELECT id, title FROM public.library_items WHERE kind = 'music' ORDER BY id;

-- ======================== patch_272_moderation_hide_and_appeal.sql ========================
-- ============================================================================
--  patch_272 — moderators can hide a single listing or post; members appeal
--  STATUS: DRAFT, NOT YET RUN. Owner to run in the SQL editor.
--  (Replaces the earlier, never-run patch_272_admin_product_moderation.sql.)
-- ============================================================================
--
--  Founder, 28 Oct 2026: "ban a post and it will stop appearing, and the
--  person will get a notification, and an option to appeal".
--
--  What exists before this patch:
--    * Only a seller can change their own listing (`products_update_self`),
--      and only an author their own post (`posts_update_self`). Moderators
--      could approve or reject a whole shop, nothing smaller.
--    * Listings 42, 43, 44 were hidden (status 'removed') on 28 Oct — but a
--      seller can set status back to 'available' from their dashboard, so
--      that "ban" can be undone by the person banned.
--    * Posts have no hidden state at all.
--
--  This patch:
--    1. adds moderation_hidden_at / moderation_reason to products and posts;
--    2. a trigger so only super admins change those columns, and a seller
--       cannot re-show a listing the moderators hid (editing it is fine —
--       that is how they fix it before appealing);
--    3. a RESTRICTIVE select policy so a hidden post disappears for everyone
--       except its author and super admins (the feed reads `posts` directly),
--       and a select policy so super admins can open a hidden listing to
--       restore it after an appeal;
--    4. admin_set_product_status / admin_set_post_hidden, gated on
--       is_super_admin(), which also notify the member with
--       reference_type 'moderated_product' / 'moderated_post' — the app
--       opens the Appeal screen (email / WhatsApp) for those;
--    5. backfills 42, 43, 44 as moderator-hidden.
--
--  CLAUDE.md checklist: not `profiles`. posts/products have table-level
--  SELECT/UPDATE for `authenticated`, so the new columns are readable (the
--  author's app needs them to show "hidden — appeal") and are protected by
--  the trigger, not by grants. BEFORE UPDATE only; returns COALESCE(NEW,OLD).
-- ============================================================================

BEGIN;

-- 1. Columns ------------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS moderation_hidden_at timestamptz,
  ADD COLUMN IF NOT EXISTS moderation_reason    text;
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS moderation_hidden_at timestamptz,
  ADD COLUMN IF NOT EXISTS moderation_reason    text;

-- 2. Guard trigger ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_moderation_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  -- SQL editor / service role (no JWT) and super admins are not limited.
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Members can never set or clear a moderation decision themselves.
  NEW.moderation_hidden_at := OLD.moderation_hidden_at;
  NEW.moderation_reason    := OLD.moderation_reason;

  -- A listing the moderators hid stays hidden until they restore it.
  IF TG_TABLE_NAME = 'products'
     AND OLD.moderation_hidden_at IS NOT NULL
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'This listing was hidden by the moderators. Appeal to have it reviewed.'
      USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS products_guard_moderation ON public.products;
CREATE TRIGGER products_guard_moderation
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.guard_moderation_columns();

DROP TRIGGER IF EXISTS posts_guard_moderation ON public.posts;
CREATE TRIGGER posts_guard_moderation
  BEFORE UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.guard_moderation_columns();

-- 3. Hidden posts vanish for everyone but the author and admins ---------------
DROP POLICY IF EXISTS posts_hide_moderated ON public.posts;
CREATE POLICY posts_hide_moderated ON public.posts
  AS RESTRICTIVE FOR SELECT
  USING (moderation_hidden_at IS NULL
         OR author_id = auth.uid()
         OR public.is_super_admin());

-- 3b. Super admins can read hidden listings ---------------------------------
-- products_select_visible lets only the seller read a 'removed' listing, so
-- a moderator could not open one to restore it after an appeal.
DROP POLICY IF EXISTS products_select_admin ON public.products;
CREATE POLICY products_select_admin ON public.products
  FOR SELECT
  USING (public.is_super_admin());

-- 4a. Hide / restore a listing ------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_product_status(
  p_product_id bigint,
  p_status     text,
  p_reason     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_seller uuid;
  v_title  text;
  v_reason text := COALESCE(NULLIF(trim(p_reason), ''),
                            'It broke the marketplace guidelines.');
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'only a super admin can moderate listings' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('available', 'removed') THEN
    RAISE EXCEPTION 'unsupported status %', p_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.products
     SET status               = p_status,
         moderation_hidden_at = CASE WHEN p_status = 'removed' THEN now() END,
         moderation_reason    = CASE WHEN p_status = 'removed' THEN v_reason END
   WHERE id = p_product_id
  RETURNING seller_id, title INTO v_seller, v_title;

  IF v_seller IS NULL THEN
    RAISE EXCEPTION 'product % not found', p_product_id USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    v_seller,
    CASE WHEN p_status = 'removed' THEN 'A listing was hidden'
         ELSE 'Your listing is back' END,
    CASE WHEN p_status = 'removed'
         THEN '"' || v_title || '" was hidden by the moderators. ' || v_reason
              || ' If you believe this is a mistake, tap to appeal.'
         ELSE '"' || v_title || '" is visible to buyers again.' END,
    'moderation',
    p_product_id::text,
    CASE WHEN p_status = 'removed' THEN 'moderated_product' ELSE 'product' END
  );
END;
$function$;

-- 4b. Hide / restore a post ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_post_hidden(
  p_post_id uuid,
  p_hidden  boolean,
  p_reason  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_author uuid;
  v_snip   text;
  v_reason text := COALESCE(NULLIF(trim(p_reason), ''),
                            'It broke the community guidelines.');
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'only a super admin can moderate posts' USING ERRCODE = '42501';
  END IF;

  UPDATE public.posts
     SET moderation_hidden_at = CASE WHEN p_hidden THEN now() END,
         moderation_reason    = CASE WHEN p_hidden THEN v_reason END
   WHERE id = p_post_id
  RETURNING author_id, left(coalesce(nullif(trim(body), ''), 'your photo post'), 60)
       INTO v_author, v_snip;

  IF v_author IS NULL THEN
    RAISE EXCEPTION 'post % not found', p_post_id USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    v_author,
    CASE WHEN p_hidden THEN 'A post was hidden' ELSE 'Your post is back' END,
    CASE WHEN p_hidden
         THEN 'Your post "' || v_snip || '" was hidden by the moderators. ' || v_reason
              || ' If you believe this is a mistake, tap to appeal.'
         ELSE 'Your post "' || v_snip || '" is visible again.' END,
    'moderation',
    p_post_id::text,
    CASE WHEN p_hidden THEN 'moderated_post' ELSE 'post' END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_product_status(bigint, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_post_hidden(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_product_status(bigint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_post_hidden(uuid, boolean, text) TO authenticated;

-- 5. Backfill the three listings hidden on 28 Oct 2026 -------------------------
UPDATE public.products
   SET moderation_hidden_at = now(),
       moderation_reason    = 'It claims to treat a medical condition, which the marketplace guidelines do not allow.'
 WHERE id IN (42, 43, 44) AND status = 'removed' AND moderation_hidden_at IS NULL;

UPDATE public.notifications
   SET type = 'moderation', reference_type = 'moderated_product'
 WHERE reference_type = 'product' AND reference_id IN ('42', '43', '44')
   AND title = 'A listing was hidden';

COMMIT;

-- Checks:
--   SELECT id, status, moderation_hidden_at FROM products WHERE id IN (42,43,44);
--   -- as the seller in the app: "Show" on a hidden listing → refused.
--   -- as a super admin: post ⋮ → Hide post → the author sees it with an
--   --   Appeal banner; nobody else sees it.

-- ======================== patch_273_saved_and_hidden_posts.sql ========================
-- ============================================================================
--  patch_273 — Save post and Hide post ("see less") for members
--  STATUS: DRAFT, NOT YET RUN. Owner to run in the SQL editor.
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

-- ======================== patch_274_followers_and_private_profiles.sql ========================
-- ============================================================================
--  patch_274 — one-way followers alongside friends; private profiles; links
--  STATUS: DRAFT, NOT YET RUN. Owner to run in the SQL editor.
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

-- ======================== patch_275_organization_pages.sql ========================
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

-- ======================== patch_277_product_views.sql ========================
-- ============================================================================
--  patch_277 — real product view counts + server-side medical-claims rule
--  STATUS: DRAFT, NOT YET RUN. Run AFTER patch_276.
-- ============================================================================
--
--  The seller dashboard has always shown a VIEWS number, read from
--  products.view_count — and nothing anywhere ever incremented it (checked
--  28 Oct 2026: no function touches the column, total views = 0). Every
--  seller saw "0 views" no matter how many people opened their listings.
--
--  This adds the counter:
--    * record_product_view(p_product) — called by the app when a signed-in
--      buyer opens a listing. Counts at most once per viewer per listing
--      per day (product_views is the dedupe ledger), never the seller
--      themselves, and only listings that are for sale.
--    * It sets app.recording_view for its own transaction so patch_276's
--      guard lets exactly this write through; nobody can set view_count
--      directly.
--
--  Also: the "no medical claims" listing rule (lib/utils/medical_claims.dart)
--  only ran in the app, so a listing could be saved straight through the
--  API. The same word list now runs as a trigger. Checked 28 Oct: the only
--  matching listings are 42–44, already removed. KEEP THE TWO LISTS IN STEP.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.product_views (
  product_id bigint NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  viewer_id  uuid   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day        date   NOT NULL DEFAULT current_date,
  PRIMARY KEY (product_id, viewer_id, day)
);
ALTER TABLE public.product_views ENABLE ROW LEVEL SECURITY;
-- No policies: only the function below reads or writes it.
REVOKE ALL ON public.product_views FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_product_view(p_product bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_inserted int;
BEGIN
  IF v_me IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products
                 WHERE id = p_product AND status = 'available'
                   AND seller_id <> v_me) THEN
    RETURN;
  END IF;
  INSERT INTO public.product_views (product_id, viewer_id)
  VALUES (p_product, v_me)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN RETURN; END IF;
  PERFORM set_config('app.recording_view', 'on', true);
  UPDATE public.products SET view_count = COALESCE(view_count, 0) + 1
   WHERE id = p_product;
  PERFORM set_config('app.recording_view', 'off', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.record_product_view(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_view(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.products_block_medical_claims()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_hit text;
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  v_hit := substring(
    lower(coalesce(NEW.title, '') || ' ' || coalesce(NEW.description, '')
          || ' ' || coalesce(NEW.subcategory, ''))
    FROM '\m(cure|cures|diabetes|diabetic|blood sugar|hypertension|high blood pressure|cancer|tumor|tumour|hiv|warts|genital|std|stds|sti|stis|herpes|syphilis|gonorrhea|gonorrhoea|covid|malaria|tuberculosis|asthma|arthritis|infertility|erectile|impotence|ulcer|ulcers|epilepsy|hepatitis|kidney disease|heart disease|cholesterol)\M');
  IF v_hit IS NOT NULL THEN
    RAISE EXCEPTION 'MEDICAL_CLAIM'
      USING ERRCODE = '42501',
            HINT = 'Listings may not say a product treats, cures or prevents a '
                || 'disease or condition (found: ' || v_hit || ').';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS products_block_medical_claims_trg ON public.products;
CREATE TRIGGER products_block_medical_claims_trg
  BEFORE INSERT OR UPDATE OF title, description, subcategory ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.products_block_medical_claims();

COMMIT;

-- Check: listing "Diabetes kit" from the API is refused (MEDICAL_CLAIM).
-- Check: open someone else's listing from another account → its seller's
-- dashboard VIEWS goes up by one; reopening the same day doesn't add more.

-- ======================== patch_278_jobs_redesign.sql ========================
-- ============================================================================
--  patch_278 — Jobs: moderation guard, apply details, company Pages, saved
--  STATUS: DRAFT, NOT YET RUN. Run AFTER 275 (company Pages) and 276.
-- ============================================================================
--
--  1. SECURITY. `authenticated` may update every column of its own jobs
--     and the only check is "it's your row", so a poster could:
--       * insert a job already 'open', skipping review (jobs default to
--         'pending' since patch_109, but the client can send a status);
--       * flip 'pending' or 'rejected' to 'open' — publish what the
--         moderators refused;
--       * push expires_at years ahead.
--     The guard lets the real paths through and nothing else:
--       * super admins + server work (admin_approve_job / admin_reject_job
--         run as the admin);
--       * poster: open ⇄ filled, open → closed (the app's Mark as filled /
--         Reopen), and renew_job's expired → open with a fresh 30 days;
--       * editing the scam-relevant fields of a LIVE job (title, employer,
--         contact phone/email, apply link, salary, linked Page) sends it
--         back to 'pending' for another look — an approved listing can't
--         be quietly turned into a different one.
--
--  2. New listing fields the redesigned form collects:
--       work_arrangement  on_site | remote | hybrid
--       apply_instructions  free text ("Send CV and two references…")
--       apply_url  http(s) link to an application form
--       page_id  the employer's organization Page (patch_275) — the
--                company profile. Only an admin of that Page can link it;
--                the Page's own verification is what shows as verified.
--
--  3. saved_jobs — each member's private list.
--
--  4. Jobs for every kind of work (owner, 28 Oct 2026: "garden boys, house
--     girls … medical … professional — it should accommodate everyone"):
--       job_type 'casual' (day / piece work); three new fields
--       (cleaning_security, hospitality_retail, creative_media);
--       structured pay — pay_min, pay_max, pay_period (hour/day/week/
--       month/year/job), pay_currency — so "$15 a day" reads as such;
--       is_urgent ("Start now").
--
--  5. BUG: renew_job set status = 'active' on an expired job. 'active'
--     isn't an allowed status (jobs_status_check), so renewing an expired
--     job has ALWAYS failed. It now sets 'open'.
--
--  6. job_applications — Quick apply inside the app. The applicant sends
--     a short message + phone; the poster is notified (push), sees an
--     Applicants list and can shortlist (applicant notified) or decline.
--     Posters only ever see applications to their own jobs; applicants
--     only their own. Max 30 applications a day per member.
--     job_applicant_count() — the real number, for "5 people applied".
--
--  7. job_alerts — "tell me when a nurse job is posted in Zimbabwe". When a
--     moderator approves a matching vacancy, each subscriber gets one
--     notification (push via the existing notifications trigger; Sabbath
--     suppression applies as for everything else). Max 10 alerts each.
--
--  CLAUDE.md: BEFORE triggers return COALESCE(NEW, OLD).
-- ============================================================================

BEGIN;

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS work_arrangement text,
  ADD COLUMN IF NOT EXISTS apply_instructions text,
  ADD COLUMN IF NOT EXISTS apply_url text,
  ADD COLUMN IF NOT EXISTS page_id uuid REFERENCES public.pages(id) ON DELETE SET NULL;

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_work_arrangement_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_work_arrangement_check
  CHECK (work_arrangement IS NULL OR work_arrangement IN ('on_site', 'remote', 'hybrid'));
ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_apply_url_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_apply_url_check
  CHECK (apply_url IS NULL OR (length(apply_url) <= 300 AND apply_url ~* '^https?://[^\s]+$'));
ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_apply_instructions_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_apply_instructions_check
  CHECK (apply_instructions IS NULL OR length(apply_instructions) <= 1000);

-- 4. Every kind of work -------------------------------------------------------
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS pay_min numeric(12,2),
  ADD COLUMN IF NOT EXISTS pay_max numeric(12,2),
  ADD COLUMN IF NOT EXISTS pay_period text,
  ADD COLUMN IF NOT EXISTS pay_currency text,
  ADD COLUMN IF NOT EXISTS is_urgent boolean NOT NULL DEFAULT false;

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_pay_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_pay_check CHECK (
      (pay_min IS NULL OR pay_min >= 0)
  AND (pay_max IS NULL OR pay_max >= 0)
  AND (pay_min IS NULL OR pay_max IS NULL OR pay_max >= pay_min)
  AND (pay_period IS NULL OR pay_period IN ('hour','day','week','month','year','job'))
  AND (pay_currency IS NULL OR pay_currency ~ '^[A-Z]{3}$'));

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_job_type_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_job_type_check CHECK (job_type = ANY (ARRAY[
  'full_time','part_time','contract','casual','internship','volunteer']));

ALTER TABLE public.jobs DROP CONSTRAINT IF EXISTS jobs_category_check;
ALTER TABLE public.jobs ADD CONSTRAINT jobs_category_check CHECK (category = ANY (ARRAY[
  'teaching_education','healthcare','construction_trades','farming_agriculture',
  'driving_transport','domestic_caregiving','business_admin','it_technology',
  'ministry_church','cleaning_security','hospitality_retail','creative_media',
  'other']));

CREATE INDEX IF NOT EXISTS jobs_open_feed
  ON public.jobs (country, created_at DESC) WHERE status = 'open';

CREATE INDEX IF NOT EXISTS jobs_page ON public.jobs (page_id) WHERE page_id IS NOT NULL;

-- 1. Guard -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.jobs_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_ok boolean;
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Linking a company Page needs to be one of its admins.
  IF NEW.page_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.page_id IS DISTINCT FROM OLD.page_id)
     AND NOT public.can_edit_page(NEW.page_id) THEN
    RAISE EXCEPTION 'Only an admin of that Page can post jobs for it.'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.expires_at := now() + interval '30 days';
    NEW.poster_id := auth.uid();
    RETURN COALESCE(NEW, OLD);
  END IF;

  NEW.poster_id := OLD.poster_id;
  NEW.created_at := OLD.created_at;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_ok := (OLD.status = 'open'   AND NEW.status IN ('filled', 'closed'))
         OR (OLD.status = 'filled' AND NEW.status = 'open')
         -- renew_job: expired → open with a fresh 30 days
         OR (OLD.status = 'expired' AND NEW.status = 'open'
             AND NEW.expires_at BETWEEN now() + interval '29 days'
                                    AND now() + interval '31 days');
    IF NOT v_ok THEN
      NEW.status := OLD.status;
    END IF;
  END IF;

  -- Expiry only moves by renewing (a fresh 30 days), never further.
  IF NEW.expires_at IS DISTINCT FROM OLD.expires_at
     AND NOT (NEW.expires_at BETWEEN now() + interval '29 days'
                                 AND now() + interval '31 days') THEN
    NEW.expires_at := OLD.expires_at;
  END IF;

  -- A live listing whose identity changes goes back for review.
  IF OLD.status = 'open' AND NEW.status = 'open' AND (
       NEW.title IS DISTINCT FROM OLD.title
    OR NEW.company IS DISTINCT FROM OLD.company
    OR NEW.contact_phone IS DISTINCT FROM OLD.contact_phone
    OR NEW.contact_email IS DISTINCT FROM OLD.contact_email
    OR NEW.apply_url IS DISTINCT FROM OLD.apply_url
    OR NEW.salary_range IS DISTINCT FROM OLD.salary_range
    OR NEW.pay_min IS DISTINCT FROM OLD.pay_min
    OR NEW.pay_max IS DISTINCT FROM OLD.pay_max
    OR NEW.page_id IS DISTINCT FROM OLD.page_id) THEN
    NEW.status := 'pending';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS jobs_guard_trg ON public.jobs;
-- Order with trg_jobs_auto_approve doesn't matter: the guard skips super
-- admins entirely, so their own posts are still auto-approved.
CREATE TRIGGER jobs_guard_trg BEFORE INSERT OR UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.jobs_guard();

-- 3. Saved jobs ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.saved_jobs (
  user_id    uuid   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  job_id     bigint NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, job_id)
);
ALTER TABLE public.saved_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS saved_jobs_own ON public.saved_jobs;
CREATE POLICY saved_jobs_own ON public.saved_jobs FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
REVOKE ALL ON public.saved_jobs FROM anon;
GRANT SELECT, INSERT, DELETE ON public.saved_jobs TO authenticated;

-- 5. renew_job: 'open', not the non-existent 'active' ------------------------
CREATE OR REPLACE FUNCTION public.renew_job(p_job_id bigint)
RETURNS public.jobs LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_row public.jobs;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to renew a job.';
  END IF;

  UPDATE public.jobs
     SET expires_at          = NOW() + INTERVAL '30 days',
         expiry_reminded_at  = NULL,
         status              = CASE WHEN status = 'expired' THEN 'open'
                                    ELSE status END
   WHERE id = p_job_id
     AND poster_id = v_caller
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Job % not found or not yours.', p_job_id;
  END IF;

  RETURN v_row;
END;
$function$;

-- 6. Applications ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_applications (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id       bigint NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  applicant_id uuid   NOT NULL DEFAULT auth.uid()
                      REFERENCES public.profiles(id) ON DELETE CASCADE,
  message      text CHECK (message IS NULL OR length(message) <= 1000),
  phone        text CHECK (phone IS NULL OR length(phone) <= 30),
  status       text NOT NULL DEFAULT 'sent'
               CHECK (status IN ('sent','viewed','shortlisted','declined')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, applicant_id)
);
CREATE INDEX IF NOT EXISTS job_applications_applicant
  ON public.job_applications (applicant_id, created_at DESC);

ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS job_applications_read ON public.job_applications;
CREATE POLICY job_applications_read ON public.job_applications FOR SELECT
  USING (applicant_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.jobs j
                     WHERE j.id = job_id AND j.poster_id = auth.uid()));

DROP POLICY IF EXISTS job_applications_apply ON public.job_applications;
CREATE POLICY job_applications_apply ON public.job_applications FOR INSERT
  WITH CHECK (applicant_id = auth.uid()
              AND public.user_is_active()
              AND EXISTS (SELECT 1 FROM public.jobs j
                           WHERE j.id = job_id
                             AND j.status = 'open'
                             AND j.post_type = 'hiring'
                             AND j.expires_at > now()
                             AND j.poster_id <> auth.uid()));

-- Only the job's poster moves the status (column grant limits it to
-- status); the applicant withdraws by deleting.
DROP POLICY IF EXISTS job_applications_review ON public.job_applications;
CREATE POLICY job_applications_review ON public.job_applications FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.jobs j
                  WHERE j.id = job_id AND j.poster_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.jobs j
                       WHERE j.id = job_id AND j.poster_id = auth.uid()));

DROP POLICY IF EXISTS job_applications_withdraw ON public.job_applications;
CREATE POLICY job_applications_withdraw ON public.job_applications FOR DELETE
  USING (applicant_id = auth.uid());

REVOKE ALL ON public.job_applications FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.job_applications TO authenticated;
GRANT UPDATE (status) ON public.job_applications TO authenticated;

CREATE OR REPLACE FUNCTION public.job_applications_before()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'sent';
    NEW.created_at := now();
    IF auth.uid() IS NOT NULL AND (
         SELECT count(*) FROM public.job_applications
          WHERE applicant_id = auth.uid()
            AND created_at > now() - interval '1 day') >= 30 THEN
      RAISE EXCEPTION 'You have sent 30 applications today. Try again tomorrow.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS job_applications_before_trg ON public.job_applications;
CREATE TRIGGER job_applications_before_trg
  BEFORE INSERT OR UPDATE ON public.job_applications
  FOR EACH ROW EXECUTE FUNCTION public.job_applications_before();

CREATE OR REPLACE FUNCTION public.job_applications_notify()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_job public.jobs;
  v_name text;
BEGIN
  SELECT * INTO v_job FROM public.jobs WHERE id = NEW.job_id;
  IF v_job.id IS NULL THEN RETURN NULL; END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT COALESCE(NULLIF(full_name, ''), 'A member') INTO v_name
      FROM public.profiles WHERE id = NEW.applicant_id;
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    VALUES (v_job.poster_id, 'New applicant',
            COALESCE(v_name, 'A member') || ' applied for "' || v_job.title || '".',
            'job_application', v_job.id::text, 'job');
  ELSIF NEW.status = 'shortlisted' AND OLD.status IS DISTINCT FROM 'shortlisted' THEN
    INSERT INTO public.notifications
      (user_id, title, body, type, reference_id, reference_type)
    VALUES (NEW.applicant_id, 'You''re shortlisted',
            'For "' || v_job.title || '". The employer may contact you soon.',
            'job_application_update', v_job.id::text, 'job');
  END IF;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS job_applications_notify_trg ON public.job_applications;
CREATE TRIGGER job_applications_notify_trg
  AFTER INSERT OR UPDATE OF status ON public.job_applications
  FOR EACH ROW EXECUTE FUNCTION public.job_applications_notify();

-- The real count, for "5 people applied" on a public job.
CREATE OR REPLACE FUNCTION public.job_applicant_count(p_job_id bigint)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.job_applications a
    JOIN public.jobs j ON j.id = a.job_id
   WHERE a.job_id = p_job_id
     AND (j.status IN ('open','filled','closed') OR j.poster_id = auth.uid());
$function$;
REVOKE ALL ON FUNCTION public.job_applicant_count(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.job_applicant_count(bigint) TO anon, authenticated;

-- 7. Alerts -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_alerts (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    uuid NOT NULL DEFAULT auth.uid()
             REFERENCES public.profiles(id) ON DELETE CASCADE,
  category   text,
  job_type   text,
  country    text,
  keyword    text CHECK (keyword IS NULL OR length(keyword) <= 60),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS job_alerts_user ON public.job_alerts (user_id);
ALTER TABLE public.job_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS job_alerts_own ON public.job_alerts;
CREATE POLICY job_alerts_own ON public.job_alerts FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
REVOKE ALL ON public.job_alerts FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.job_alerts TO authenticated;

CREATE OR REPLACE FUNCTION public.job_alerts_limit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF (SELECT count(*) FROM public.job_alerts WHERE user_id = NEW.user_id) >= 10 THEN
    RAISE EXCEPTION 'You can have up to 10 job alerts.' USING ERRCODE = 'P0001';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;
DROP TRIGGER IF EXISTS job_alerts_limit_trg ON public.job_alerts;
CREATE TRIGGER job_alerts_limit_trg BEFORE INSERT ON public.job_alerts
  FOR EACH ROW EXECUTE FUNCTION public.job_alerts_limit();

-- Fires when a vacancy goes live: moderator approval (pending → open) or a
-- super admin's own post (inserted open). One notification per member per
-- job, ever — re-approving an edited job doesn't notify twice.
CREATE OR REPLACE FUNCTION public.jobs_notify_alerts()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_where text;
BEGIN
  IF NEW.status <> 'open' OR NEW.post_type <> 'hiring' THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status <> 'pending' THEN RETURN NULL; END IF;
  IF NEW.expires_at IS NOT NULL AND NEW.expires_at <= now() THEN RETURN NULL; END IF;

  v_where := concat_ws(' · ', NULLIF(NEW.company, ''), NULLIF(NEW.location, ''));

  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  SELECT DISTINCT a.user_id,
         'New job: ' || NEW.title,
         COALESCE(NULLIF(v_where, ''), 'Matches your job alert'),
         'job_alert', NEW.id::text, 'job'
    FROM public.job_alerts a
   WHERE a.user_id <> NEW.poster_id
     AND (a.category IS NULL OR a.category = NEW.category)
     AND (a.job_type IS NULL OR a.job_type = NEW.job_type)
     AND (a.country  IS NULL OR a.country  = NEW.country)
     AND (a.keyword  IS NULL
          OR NEW.title ILIKE '%' || a.keyword || '%'
          OR NEW.description ILIKE '%' || a.keyword || '%')
     AND NOT EXISTS (SELECT 1 FROM public.notifications n
                      WHERE n.user_id = a.user_id
                        AND n.type = 'job_alert'
                        AND n.reference_id = NEW.id::text);
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS jobs_notify_alerts_trg ON public.jobs;
CREATE TRIGGER jobs_notify_alerts_trg
  AFTER INSERT OR UPDATE OF status ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.jobs_notify_alerts();

COMMIT;

-- Checks (as an ordinary member):
--   * Post a job from the API with status 'open' → it lands 'pending'.
--   * PATCH a rejected job to 'open' → stays rejected.
--   * Change the phone number on a live job → back to 'pending'.
--   * Mark as filled / Reopen / Renew → work as before.
--   * Super admin approve / reject → work as before.
--   * Renew an EXPIRED job → it comes back 'open' (used to error).
--   * Apply to someone else's open vacancy → poster gets "New applicant";
--     apply to your own / a pending job → refused.
--   * Poster shortlists → applicant gets "You're shortlisted".
--   * Create an alert (category healthcare, country ZW), approve a
--     matching job as admin → one "New job: …" notification.

-- ======================== patch_279_report_takedowns.sql ========================
-- ============================================================================
--  patch_279 — reports you can act on: see what was reported, take it down,
--  ban the person behind it
--  STATUS: DRAFT, NOT YET RUN. Run AFTER 272, 275, 276 and 278.
-- ============================================================================
--
--  Owner, 28 Oct 2026: "is there an option to report jobs … products …
--  stores? … it will get to my admin dashboard. Then I will ban if it's
--  necessary."
--
--  Before this patch:
--    * The app already had Report on jobs, products and stores, and the
--      reports reached the dashboard's Reports queue — but the queue showed
--      only "product" and an id, not WHICH listing or WHO posted it.
--    * "Ban" existed only for reports against a person. For a reported job,
--      product or store the only button was "Resolve" (a note) — nothing
--      actually came down.
--    * A banned member can't post anything new (user_is_active()), but what
--      they had already posted stayed live.
--    * The same member could file the same report again and again.
--
--  This patch:
--    1. reports.reported_user_id is filled by the SERVER for jobs, products,
--       stores, Pages and people (the column existed for messages only), so
--       a report can't point at the wrong person; old reports backfilled.
--    2. One open report per member per item (a repeat is a no-op).
--    3. admin_list_reports also returns what was reported (title, a short
--       preview, its current state), who is behind it (name, banned?) and
--       how many open reports that item has.
--    4. admin_takedown_report(report, reason, ban):
--         job → status 'rejected' (gone from the board), poster notified;
--         product → admin_set_product_status('removed') from patch_272
--                   (seller notified, can appeal);
--         store → status 'rejected_final', closed, its listings removed,
--                 owner notified;
--         Page → hidden via admin_set_page_state (patch_275);
--         post → admin_set_post_hidden (patch_272);
--       then, if ban = true, bans the person (admin_set_banned: refuses to
--       ban yourself or another super admin, notifies them) AND takes down
--       everything else they have live — open jobs, listings, their store.
--       Every open report on that item is closed as actioned.
--
--  Super admins only (is_super_admin), like every other report function.
--  CLAUDE.md: not `profiles` columns; BEFORE trigger returns COALESCE.
-- ============================================================================

BEGIN;

-- 1. Who is behind the reported item -----------------------------------------
CREATE OR REPLACE FUNCTION public.report_owner(p_type text, p_id text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v uuid;
  v_num boolean := p_id ~ '^\d+$';
  v_uuid boolean := p_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
  CASE p_type
    WHEN 'job' THEN
      IF v_num THEN SELECT poster_id INTO v FROM jobs WHERE id = p_id::bigint; END IF;
    WHEN 'product' THEN
      IF v_num THEN SELECT seller_id INTO v FROM products WHERE id = p_id::bigint; END IF;
    WHEN 'seller' THEN
      -- The storefront reports the owner's account id; older builds the row id.
      IF v_uuid THEN v := p_id::uuid;
      ELSIF v_num THEN SELECT auth_user_id INTO v FROM sellers WHERE id = p_id::bigint;
      END IF;
    WHEN 'page' THEN
      IF v_uuid THEN
        SELECT pa.user_id INTO v FROM page_admins pa
         WHERE pa.page_id = p_id::uuid AND pa.role = 'owner' LIMIT 1;
      END IF;
    WHEN 'post' THEN
      IF v_uuid THEN SELECT author_id INTO v FROM posts WHERE id = p_id::uuid; END IF;
    WHEN 'user', 'profile' THEN
      IF v_uuid THEN v := p_id::uuid; END IF;
    ELSE
      v := NULL;
  END CASE;
  RETURN v;
EXCEPTION WHEN undefined_table OR undefined_column THEN
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.report_owner(text, text) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reports_fill_owner()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  -- Messages are stamped by report_message() (patch_165); keep that.
  IF NEW.content_type <> 'message' THEN
    NEW.reported_user_id := public.report_owner(NEW.content_type, NEW.content_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS reports_fill_owner_trg ON public.reports;
CREATE TRIGGER reports_fill_owner_trg BEFORE INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.reports_fill_owner();

UPDATE public.reports
   SET reported_user_id = public.report_owner(content_type, content_id)
 WHERE reported_user_id IS NULL AND content_type <> 'message';

-- 2. One open report per member per item ----------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS reports_one_open_per_member
  ON public.reports (reported_by, content_type, content_id)
  WHERE status IN ('pending', 'reviewing');

-- 3. The queue, with what and who ---------------------------------------------
DROP FUNCTION IF EXISTS public.admin_list_reports(text, integer);
CREATE FUNCTION public.admin_list_reports(
  p_status text DEFAULT 'pending', p_limit integer DEFAULT 100)
RETURNS TABLE(
  id bigint, reported_by uuid, reporter_name text,
  content_type text, content_id text, reason text, details text,
  status text, action_taken text, created_at timestamptz,
  content_title text, content_preview text, content_state text,
  reported_user_id uuid, reported_user_name text, reported_user_banned boolean,
  open_reports_on_content integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_status text := CASE WHEN p_status = 'open' THEN 'pending' ELSE p_status END;
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    WITH r AS (
      SELECT r.*,
             r.content_id ~ '^\d+$' AS is_num,
             r.content_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AS is_uuid
        FROM public.reports r
       WHERE (v_status = 'all' OR COALESCE(r.status, 'pending') = v_status)
       ORDER BY r.created_at DESC
       LIMIT GREATEST(p_limit, 1)
    )
    SELECT r.id, r.reported_by,
           COALESCE(NULLIF(btrim(rp.full_name), ''), 'Member'),
           r.content_type, r.content_id, r.reason, r.details,
           COALESCE(r.status, 'pending'), r.action_taken, r.created_at,
           COALESCE(j.title, pr.title, s.business_name, pg.name, op.full_name,
                    left(po.body, 80), left(r.reported_text, 80)),
           left(COALESCE(j.description, pr.description, s.description,
                         pg.description, po.body, r.reported_text), 200),
           COALESCE(j.status, pr.status, s.status, pg.status,
                    CASE WHEN op.is_banned THEN 'banned' END),
           r.reported_user_id,
           NULLIF(btrim(owner.full_name), ''),
           COALESCE(owner.is_banned, false),
           (SELECT count(*)::int FROM public.reports x
             WHERE x.content_type = r.content_type
               AND x.content_id = r.content_id
               AND x.status IN ('pending', 'reviewing'))
      FROM r
      LEFT JOIN public.profiles rp ON rp.id = r.reported_by
      LEFT JOIN public.profiles owner ON owner.id = r.reported_user_id
      LEFT JOIN public.jobs j
             ON r.content_type = 'job' AND r.is_num AND j.id = r.content_id::bigint
      LEFT JOIN public.products pr
             ON r.content_type = 'product' AND r.is_num AND pr.id = r.content_id::bigint
      LEFT JOIN public.sellers s
             ON r.content_type = 'seller'
            AND ((r.is_uuid AND s.auth_user_id = r.content_id::uuid)
              OR (r.is_num AND s.id = r.content_id::bigint))
      LEFT JOIN public.pages pg
             ON r.content_type = 'page' AND r.is_uuid AND pg.id = r.content_id::uuid
      LEFT JOIN public.posts po
             ON r.content_type = 'post' AND r.is_uuid AND po.id = r.content_id::uuid
      LEFT JOIN public.profiles op
             ON r.content_type IN ('user', 'profile') AND r.is_uuid
            AND op.id = r.content_id::uuid
     ORDER BY r.created_at DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_reports(text, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_reports(text, integer) TO authenticated;

-- 4. Take it down (and optionally ban) ---------------------------------------
-- Removes one item. Internal: callers check is_super_admin().
CREATE OR REPLACE FUNCTION public.moderation_remove_item(
  p_type text, p_id text, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_owner uuid;
  v_title text;
  v_seller public.sellers;
BEGIN
  CASE p_type
    WHEN 'job' THEN
      UPDATE jobs SET status = 'rejected'
       WHERE id = p_id::bigint AND status <> 'rejected'
      RETURNING poster_id, title INTO v_owner, v_title;
      IF v_owner IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, reference_id, reference_type)
        VALUES (v_owner, 'Job removed',
                '"' || v_title || '" was removed by the moderators: ' || p_reason
                  || ' Contact support if you believe this is a mistake.',
                'moderation', p_id, 'job');
      END IF;
    WHEN 'product' THEN
      PERFORM public.admin_set_product_status(p_id::bigint, 'removed', p_reason);
    WHEN 'seller' THEN
      IF p_id ~ '^\d+$' THEN
        SELECT * INTO v_seller FROM sellers WHERE id = p_id::bigint;
      ELSE
        SELECT * INTO v_seller FROM sellers WHERE auth_user_id = p_id::uuid;
      END IF;
      IF v_seller.id IS NOT NULL THEN
        UPDATE sellers
           SET status = 'rejected_final', is_active = false,
               rejection_reason = p_reason
         WHERE id = v_seller.id;
        -- A closed store's listings come down with it.
        UPDATE products
           SET status = 'removed', moderation_hidden_at = now(),
               moderation_reason = p_reason
         WHERE seller_id = v_seller.auth_user_id AND status <> 'removed';
        INSERT INTO notifications (user_id, title, body, type, reference_id, reference_type)
        VALUES (v_seller.auth_user_id, 'Store closed',
                v_seller.business_name || ' was closed by the moderators: ' || p_reason
                  || ' Contact support if you believe this is a mistake.',
                'moderation', v_seller.id::text, 'seller');
      END IF;
    WHEN 'page' THEN
      PERFORM public.admin_set_page_state(
        p_id::uuid,
        COALESCE((SELECT is_verified FROM pages WHERE id = p_id::uuid), false),
        true, p_reason);
    WHEN 'post' THEN
      PERFORM public.admin_set_post_hidden(p_id::uuid, true, p_reason);
    ELSE
      -- People are handled by the ban; other types have no takedown yet.
      NULL;
  END CASE;
END;
$function$;
REVOKE ALL ON FUNCTION public.moderation_remove_item(text, text, text)
  FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_takedown_report(
  p_report_id bigint, p_reason text, p_ban boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  r public.reports;
  v_reason text := COALESCE(NULLIF(btrim(p_reason), ''),
                            'It broke the community guidelines.');
  v_owner uuid;
  v_action text;
  v_id text;
BEGIN
  PERFORM public.assert_super_admin();
  SELECT * INTO r FROM reports WHERE id = p_report_id;
  IF r.id IS NULL THEN
    RAISE EXCEPTION 'Report % not found.', p_report_id USING ERRCODE = 'P0002';
  END IF;

  v_owner := COALESCE(r.reported_user_id,
                      public.report_owner(r.content_type, r.content_id));

  PERFORM public.moderation_remove_item(r.content_type, r.content_id, v_reason);
  v_action := CASE WHEN r.content_type IN ('user', 'profile', 'message')
                   THEN 'Reviewed' ELSE 'Removed' END;

  IF p_ban THEN
    IF v_owner IS NULL THEN
      RAISE EXCEPTION 'No account found behind this report to ban.'
        USING ERRCODE = 'P0002';
    END IF;
    -- Refuses yourself / another super admin; notifies the member.
    PERFORM public.admin_set_banned(v_owner, true);

    -- What they already posted comes down too.
    FOR v_id IN SELECT j.id::text FROM jobs j
                 WHERE j.poster_id = v_owner AND j.status IN ('open', 'pending', 'filled')
    LOOP
      PERFORM public.moderation_remove_item('job', v_id, v_reason);
    END LOOP;
    FOR v_id IN SELECT s.id::text FROM sellers s
                 WHERE s.auth_user_id = v_owner AND s.status <> 'rejected_final'
    LOOP
      PERFORM public.moderation_remove_item('seller', v_id, v_reason);
    END LOOP;
    UPDATE products
       SET status = 'removed', moderation_hidden_at = now(),
           moderation_reason = v_reason
     WHERE seller_id = v_owner AND status <> 'removed';

    v_action := v_action || ' + banned the account and removed their listings';
  END IF;

  v_action := v_action || ': ' || v_reason;

  UPDATE reports
     SET status = 'actioned', action_taken = v_action,
         reviewed_by = auth.uid(), reviewed_at = now()
   WHERE content_type = r.content_type AND content_id = r.content_id
     AND status IN ('pending', 'reviewing');

  RETURN v_action;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_takedown_report(bigint, text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_takedown_report(bigint, text, boolean) TO authenticated;

COMMIT;

-- Checks (as a super admin, from the dashboard):
--   * Report a product from the app → the queue shows its title, the
--     seller's name and "1 open report".
--   * Report it again from the same account → still 1.
--   * "Remove" → the listing disappears for buyers; the seller gets
--     "A listing was hidden" with the appeal option; the report is actioned.
--   * "Remove & ban" on a reported job → the job is gone, the poster is
--     banned and notified, and their other jobs / store / listings are gone.
--   * Try "Remove & ban" on a report about your own listing → refused.
