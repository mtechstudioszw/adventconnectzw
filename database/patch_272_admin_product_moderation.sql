-- ============================================================================
--  patch_272 — super admins can hide or restore a single listing
--  STATUS: DRAFT, NOT YET RUN. Owner to run in the SQL editor.
-- ============================================================================
--
--  Why (28 Oct 2026): listings making disease-treatment claims ("Genital
--  warts: there is hope", "Diabetes support kit") put the app at risk with
--  Apple (guidelines 1.2 user content, 1.4.1 medical claims) and Google
--  Play. The only moderation tool was approving or rejecting a WHOLE shop —
--  `products_update_self` lets nobody but the seller change a listing.
--
--  This adds one SECURITY DEFINER function, gated on is_super_admin(), that
--  sets a listing to 'removed' (hidden from buyers, kept for the seller —
--  exactly what the seller's own "hide" does) or back to 'available', and
--  tells the seller why in their notifications.
--
--  CLAUDE.md checklist: no new columns, no triggers, no grants on tables.
--  EXECUTE is granted to `authenticated` only; the function itself refuses
--  anyone who is not a super admin.
-- ============================================================================

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
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'only a super admin can moderate listings'
      USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('available', 'removed') THEN
    RAISE EXCEPTION 'unsupported status %', p_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.products
     SET status = p_status
   WHERE id = p_product_id
  RETURNING seller_id, title INTO v_seller, v_title;

  IF v_seller IS NULL THEN
    RAISE EXCEPTION 'product % not found', p_product_id USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    v_seller,
    CASE WHEN p_status = 'removed'
         THEN 'A listing was hidden'
         ELSE 'A listing is visible again' END,
    CASE WHEN p_status = 'removed'
         THEN '"' || v_title || '" was hidden by the moderators. '
              || COALESCE(NULLIF(trim(p_reason), ''),
                          'It broke the marketplace guidelines.')
              || ' You can edit it and ask for a review.'
         ELSE '"' || v_title || '" is visible to buyers again.' END,
    'marketplace',
    p_product_id::text,
    'product'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_product_status(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_product_status(bigint, text, text) TO authenticated;

-- Check (as yourself, a super admin, in the app): open a listing → ⋮ →
-- "Hide listing". The seller sees a notification; buyers no longer see it.
