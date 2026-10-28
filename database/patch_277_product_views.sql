-- ============================================================================
--  patch_277 — real product view counts + server-side medical-claims rule
--  STATUS: APPLIED to the live database 28 Oct 2026.
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
