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
