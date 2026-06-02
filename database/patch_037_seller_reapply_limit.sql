-- =====================================================================
--  PATCH 037 — Seller reapply attempts + final-review gate
--
--  WHY: A rejected seller's "Edit store details" update was a plain
--       UPDATE on sellers — status stayed 'rejected', so the admin
--       queue (status='pending') never re-surfaced the row. The
--       application was silently lost.
--
--       Founder also wants a hard cap: 3 attempts per user. The
--       third attempt routes to a `final_review_pending` queue
--       so the admin knows this is the seller's last shot; a
--       rejection there flips the row to `rejected_final` and the
--       app permanently disables Reapply.
--
--  WHAT:
--   1. sellers.application_attempts INT NOT NULL DEFAULT 1.
--   2. Status CHECK widened to include 'final_review_pending' and
--      'rejected_final'.
--   3. RPC seller_reapply(p_seller_id BIGINT) — owner-only, flips
--      a rejected row back into review (pending or final_review
--      _pending based on attempt count), increments the counter,
--      clears rejection_reason.
--   4. RPC admin_reject_seller updated — on final_review_pending
--      it transitions to rejected_final (permanent), with an
--      explicit "marketplace access closed" notification. Reasons
--      for 2nd-attempt rejection now warn the seller they have one
--      attempt left.
--   5. RPC admin_pending_sellers returns BOTH pending and
--      final_review_pending so the admin queue sees the final
--      review.
--
--  PREREQUISITES: patch_031 (admin RPCs + view).
--  IDEMPOTENT:    yes — IF NOT EXISTS + CREATE OR REPLACE.
-- =====================================================================


-- ----- 1. application_attempts column --------------------------------
ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS application_attempts INT NOT NULL DEFAULT 1;


-- ----- 2. Widened status CHECK --------------------------------------
ALTER TABLE public.sellers
  DROP CONSTRAINT IF EXISTS sellers_status_check;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_status_check CHECK (
    status IN (
      'pending',
      'approved',
      'rejected',
      'final_review_pending',
      'rejected_final'
    )
  );


-- ----- 3. seller_reapply --------------------------------------------
CREATE OR REPLACE FUNCTION public.seller_reapply(
  p_seller_id BIGINT
)
RETURNS public.sellers AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_row public.sellers;
  v_new_attempts INT;
  v_new_status TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to reapply.';
  END IF;

  SELECT *
    INTO v_row
    FROM public.sellers
   WHERE id = p_seller_id
     AND auth_user_id = v_caller;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Seller % not found or not yours.', p_seller_id;
  END IF;

  IF v_row.status <> 'rejected' THEN
    RAISE EXCEPTION
      'Only rejected applications can be re-submitted. Current status: %.',
      v_row.status;
  END IF;

  v_new_attempts := COALESCE(v_row.application_attempts, 1) + 1;
  IF v_new_attempts > 3 THEN
    RAISE EXCEPTION 'You have used all 3 application attempts.';
  END IF;

  -- The third attempt is the seller's last shot — surface it as a
  -- separate queue so the admin treats it as such.
  v_new_status := CASE
    WHEN v_new_attempts >= 3 THEN 'final_review_pending'
    ELSE 'pending'
  END;

  UPDATE public.sellers
     SET status                = v_new_status,
         rejection_reason      = NULL,
         application_attempts  = v_new_attempts,
         is_active             = FALSE
   WHERE id = p_seller_id
  RETURNING * INTO v_row;

  -- Confirmation back to the seller. Helpful as a paper trail when
  -- the admin eventually re-reviews ("you said you submitted...").
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_row.auth_user_id,
    CASE WHEN v_new_status = 'final_review_pending'
      THEN 'Application resubmitted (final review)'
      ELSE 'Application resubmitted'
    END,
    CASE WHEN v_new_status = 'final_review_pending'
      THEN 'This is your final attempt. An admin will review your updated details — please ensure everything is accurate.'
      ELSE 'We received your updated details. An admin will review again — you''ll get a notification when there''s a decision.'
    END,
    'seller_resubmitted',
    v_row.id::text,
    'seller'
  );

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.seller_reapply(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seller_reapply(BIGINT) TO authenticated;


-- ----- 4. Updated admin_reject_seller --------------------------------
CREATE OR REPLACE FUNCTION public.admin_reject_seller(
  p_seller_id BIGINT,
  p_reason    TEXT
)
RETURNS public.sellers AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_is_admin BOOLEAN;
  v_row public.sellers;
  v_clean_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
  v_current_status TEXT;
  v_attempts INT;
  v_new_status TEXT;
  v_title TEXT;
  v_body TEXT;
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

  SELECT status, COALESCE(application_attempts, 1)
    INTO v_current_status, v_attempts
    FROM public.sellers
   WHERE id = p_seller_id;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'Seller % not found.', p_seller_id;
  END IF;

  -- A third-attempt rejection is terminal — flip to rejected_final
  -- and tell the seller marketplace access is closed.
  IF v_current_status = 'final_review_pending' THEN
    v_new_status := 'rejected_final';
    v_title := 'Seller application closed';
    v_body := COALESCE(
      v_clean_reason,
      'Your seller application has been rejected 3 times. You are no longer eligible to apply to become a marketplace seller. Please contact support for more information.'
    );
  ELSE
    v_new_status := 'rejected';
    IF v_attempts >= 2 THEN
      -- Second rejection — warn this is the last chance.
      v_title := 'Application rejected (final attempt remaining)';
      v_body := COALESCE(
        v_clean_reason,
        'Your seller application was rejected again. Please review your details carefully — this is your final attempt before marketplace access is closed.'
      );
    ELSE
      v_title := 'Application rejected';
      v_body := COALESCE(
        v_clean_reason,
        'Your seller application was rejected. Please update your store information and reapply.'
      );
    END IF;
  END IF;

  UPDATE public.sellers
     SET status           = v_new_status,
         rejection_reason = v_clean_reason,
         is_active        = FALSE
   WHERE id = p_seller_id
  RETURNING * INTO v_row;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_row.auth_user_id,
    v_title,
    v_body,
    'seller_rejected',
    v_row.id::text,
    'seller'
  );

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_reject_seller(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_seller(BIGINT, TEXT) TO authenticated;


-- ----- 5. admin_pending_sellers now returns both queues --------------
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
     WHERE status IN ('pending', 'final_review_pending')
     ORDER BY status DESC,             -- final_review first
              created_at DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_pending_sellers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_sellers() TO authenticated;
