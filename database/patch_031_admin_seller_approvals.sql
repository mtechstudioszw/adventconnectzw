-- =====================================================================
--  PATCH 031 — Admin-vetted seller approvals (reverse of patch_022)
--
--  WHY: Founder direction (2026-05-31): the self-serve seller flow let
--       anyone publish a storefront the moment they accepted the Code
--       of Conduct. Spam + low-quality stores started slipping in. We
--       still want the apply-for-business indirection gone (that's
--       deleted from the app layer in the same commit), but a brand
--       new seller profile must now sit as `pending` until a super
--       admin approves it. After one approval the seller can list /
--       edit / hide products freely — no further per-product review.
--
--  WHAT:
--   1. Flip sellers.status default back to 'pending' for NEW inserts.
--      Existing approved sellers are unchanged (they keep selling).
--   2. RPC `admin_approve_seller(p_seller_id UUID)` — super-admin only.
--   3. RPC `admin_reject_seller(p_seller_id UUID, p_reason TEXT)` —
--      super-admin only, stamps rejection_reason + status='rejected'.
--   4. RPC `admin_pending_sellers()` — super-admin only, returns the
--      queue of pending rows newest-first.
--   5. View `marketplace_products_public` — products WHERE seller is
--      approved AND active. The app's marketplace listing query joins
--      this view via seller_id, so products from pending / rejected
--      / banned sellers never reach buyers even if RLS lets them
--      through to a curious dev.
--
--  PREREQUISITES: schema.sql + patch_022 + patch_023.
--  IDEMPOTENT:    yes — CREATE OR REPLACE / IF NOT EXISTS throughout.
-- =====================================================================


-- ----- 1. Flip the default back to 'pending' ------------------------
ALTER TABLE public.sellers
  ALTER COLUMN status SET DEFAULT 'pending';

-- The CHECK from patch_022 (terms accepted before approved/active) is
-- still correct — pending rows don't require terms_accepted_at, but the
-- app still writes it on insert because the Code of Conduct gate is
-- still part of the setup flow.


-- ----- 2. admin_approve_seller --------------------------------------
CREATE OR REPLACE FUNCTION public.admin_approve_seller(
  p_seller_id UUID
)
RETURNS public.sellers AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_is_admin BOOLEAN;
  v_row public.sellers;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to approve sellers.';
  END IF;

  SELECT COALESCE(is_super_admin, FALSE)
    INTO v_is_admin
    FROM public.profiles
    WHERE id = v_caller;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Only super admins can approve sellers.';
  END IF;

  UPDATE public.sellers
     SET status             = 'approved',
         approved_at        = COALESCE(approved_at, NOW()),
         is_active          = TRUE,
         rejection_reason   = NULL,
         terms_accepted_at  = COALESCE(terms_accepted_at, NOW()),
         terms_version      = COALESCE(terms_version, 'v1-2026-05')
   WHERE id = p_seller_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Seller % not found.', p_seller_id;
  END IF;

  -- Notify the seller their storefront is live.
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_row.auth_user_id,
    'Your store is live',
    'Welcome to the marketplace. You can now list products.',
    'seller_approved',
    v_row.id::text,
    'seller'
  );

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_approve_seller(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_seller(UUID) TO authenticated;


-- ----- 3. admin_reject_seller ---------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reject_seller(
  p_seller_id UUID,
  p_reason    TEXT
)
RETURNS public.sellers AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_is_admin BOOLEAN;
  v_row public.sellers;
  v_clean_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to reject sellers.';
  END IF;

  SELECT COALESCE(is_super_admin, FALSE)
    INTO v_is_admin
    FROM public.profiles
    WHERE id = v_caller;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Only super admins can reject sellers.';
  END IF;

  UPDATE public.sellers
     SET status           = 'rejected',
         rejection_reason = v_clean_reason,
         is_active        = FALSE
   WHERE id = p_seller_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Seller % not found.', p_seller_id;
  END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_row.auth_user_id,
    'Store application declined',
    COALESCE(
      v_clean_reason,
      'Your store profile was not approved. Please edit it and re-submit.'
    ),
    'seller_rejected',
    v_row.id::text,
    'seller'
  );

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_reject_seller(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_seller(UUID, TEXT) TO authenticated;


-- ----- 4. admin_pending_sellers -------------------------------------
CREATE OR REPLACE FUNCTION public.admin_pending_sellers()
RETURNS SETOF public.sellers AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_is_admin BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to view pending sellers.';
  END IF;

  SELECT COALESCE(is_super_admin, FALSE)
    INTO v_is_admin
    FROM public.profiles
    WHERE id = v_caller;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Only super admins can view pending sellers.';
  END IF;

  RETURN QUERY
    SELECT *
      FROM public.sellers
     WHERE status = 'pending'
     ORDER BY created_at DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_pending_sellers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_sellers() TO authenticated;


-- ----- 5. Public marketplace view (approved sellers only) -----------
-- The app's MarketplaceService now consults `sellers` to derive the
-- visible seller_id set before fetching products. This view is a
-- safety net + lets future server-side queries skip the dance.
CREATE OR REPLACE VIEW public.marketplace_products_public AS
  SELECT p.*
    FROM public.products p
    JOIN public.sellers   s ON s.auth_user_id = p.seller_id
   WHERE p.status = 'available'
     AND s.status = 'approved'
     AND s.is_active = TRUE;

GRANT SELECT ON public.marketplace_products_public TO authenticated, anon;
