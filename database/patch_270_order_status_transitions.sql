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
