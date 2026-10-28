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
    NEW.view_count := OLD.view_count;
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
