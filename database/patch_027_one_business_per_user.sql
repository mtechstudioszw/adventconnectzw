-- patch_027_one_business_per_user.sql
--
-- WHAT:  Enforce one seller row per auth user. Stops a single Adventist
--        Connect ZW account from opening multiple storefronts, which
--        broke the "tap product → see THE seller" navigation and made
--        the marketplace look spammy when a user re-applied.
--
-- WHY:   Per founder request (2026-05-27): "one business per user".
--        Previously the sellers table allowed duplicates because the
--        only constraint was the surrogate BIGSERIAL primary key.
--
-- DOES THIS WORK ON A DB THAT ALREADY HAS DUPLICATES?
--   No — adding a UNIQUE index on a column with existing duplicate
--   values fails. The pre-check below counts duplicates and aborts
--   the patch with a clear message if any exist, so the operator
--   can resolve them manually before re-running.
--
-- ROLLBACK:  DROP INDEX IF EXISTS sellers_one_per_user_uidx;
--
-- =============================================================

DO $$
DECLARE
  dupes INT;
BEGIN
  SELECT COUNT(*) INTO dupes FROM (
    SELECT auth_user_id
    FROM public.sellers
    WHERE auth_user_id IS NOT NULL
    GROUP BY auth_user_id
    HAVING COUNT(*) > 1
  ) AS d;

  IF dupes > 0 THEN
    RAISE EXCEPTION
      'patch_027 aborted: % auth_user_id(s) have multiple seller rows. '
      'Resolve duplicates manually then re-run.', dupes;
  END IF;
END$$;

CREATE UNIQUE INDEX IF NOT EXISTS sellers_one_per_user_uidx
  ON public.sellers (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

-- Friendly error if the client side races past the existence check
-- inside SellerService.applyAsSeller(). The default Postgres message
-- ("duplicate key value violates unique constraint ...") leaks
-- internals; this CHECK-trigger fires the human-readable message
-- first.
CREATE OR REPLACE FUNCTION public.sellers_one_per_user_guard()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.sellers
    WHERE auth_user_id = NEW.auth_user_id
      AND id <> COALESCE(NEW.id, -1)
  ) THEN
    RAISE EXCEPTION
      'You already have a store on Advent Connect ZW. Edit your '
      'existing store instead of creating a new one.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sellers_one_per_user ON public.sellers;
CREATE TRIGGER trg_sellers_one_per_user
  BEFORE INSERT ON public.sellers
  FOR EACH ROW EXECUTE FUNCTION public.sellers_one_per_user_guard();
