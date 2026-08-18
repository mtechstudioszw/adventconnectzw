-- =====================================================================
--  PATCH 217 — price_currency: an ISO 4217 SHAPE, not a list of three
--
--  `products.price_currency` was CHECKed against ARRAY['USD','ZWL','ZAR'].
--  That was right when the app was Zimbabwe-only and is now the single
--  hardest blocker left for sellers outside it: a Kenyan seller cannot
--  price in KES, a Nigerian cannot price in NGN, and the insert fails with
--  a constraint violation rather than anything the app can explain.
--
--  Replaced with a FORMAT check — three capitals, the shape of every ISO
--  4217 code — rather than a longer list. Same reasoning patch_213 used
--  for `country ~ '^[A-Z]{2}$'`:
--
--    * A list of ~180 currencies would need a new patch every time a
--      country is added to lib/config/countries.dart, and the two lists
--      would drift the first time somebody forgot.
--    * The database's job here is to reject junk ('', 'dollars', '$'),
--      not to curate. WHICH currencies a seller may pick is a product
--      decision, and it lives in the app where it can be changed without
--      a migration.
--
--  Deliberately NOT touching `orders.currency` / `order_items.currency`:
--  they carry no CHECK at all and simply inherit whatever the product was
--  priced in, so widening products widens the whole chain.
--
--  DATA: every existing row is 'USD', 'ZWL' or 'ZAR', all of which match
--  the new pattern, so the constraint validates against current data
--  without a rewrite.
--
--  IDEMPOTENT: yes — both constraint names are dropped IF EXISTS before
--  the new one is added, so a re-run is a no-op rather than a
--  "constraint already exists" failure.
-- =====================================================================

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_price_currency_check;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_price_currency_iso4217;

ALTER TABLE public.products
  ADD CONSTRAINT products_price_currency_iso4217
  CHECK (price_currency IS NULL OR price_currency ~ '^[A-Z]{3}$');

-- ---------------------------------------------------------------------
--  Verification — run these and read the output.
-- ---------------------------------------------------------------------
-- SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--  WHERE conrelid='public.products'::regclass AND contype='c'
--    AND conname LIKE '%currency%';
--   -- expect: products_price_currency_iso4217, the regex form
--
-- SELECT price_currency, count(*) FROM public.products GROUP BY 1;
--   -- expect: only existing codes; nothing should have been rejected
