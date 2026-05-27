-- =====================================================================
--  PATCH 022 — Sellers go self-serve + Marketplace Code of Conduct
--
--  WHY: The original sellers flow gated every storefront on admin
--       approval (status='pending' → admin flips to 'approved'). That
--       worked when traffic was hand-curated but creates a sign-up
--       bottleneck the moment growth picks up. The new model:
--
--         - Anyone authenticated can create a storefront immediately.
--         - To create one they must first accept the Marketplace Code
--           of Conduct (Adventist-values products, Sabbath respect,
--           honesty, no alcohol/tobacco/gambling/occult).
--         - Violations → admin sets is_active = FALSE (silent take-
--           down) or status = 'banned' (permanent). Moderation is
--           reactive, not gatekeeping.
--
--  WHAT:
--   1. Default sellers.status flipped from 'pending' to 'approved' so
--      new inserts go live immediately. Existing 'pending' rows are
--      backfilled to 'approved' so legacy applicants stop hanging.
--   2. New sellers columns:
--        terms_accepted_at  TIMESTAMPTZ — when the user agreed.
--        terms_version      TEXT        — which version of the code
--                                          they agreed to (so a
--                                          future tightening can
--                                          force re-acceptance).
--   3. CHECK constraint: terms_accepted_at NOT NULL when
--      status = 'approved' OR status = 'active' — prevents anyone
--      bypassing the screen.
--   4. Index `is_active` so the marketplace listing filter is cheap.
--
--  PREREQUISITES: schema.sql + patch_002.
--  IDEMPOTENT:    yes — IF NOT EXISTS / DROP IF EXISTS throughout.
-- =====================================================================


-- ----- 1. New columns -----------------------------------------------
ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;
ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS terms_version TEXT;


-- ----- 2. Backfill legacy approved rows so the CHECK below holds ----
-- Any seller that was already 'approved' is treated as having
-- implicitly accepted the v1 code via the old application form.
UPDATE public.sellers
   SET terms_accepted_at = COALESCE(terms_accepted_at, approved_at, created_at),
       terms_version     = COALESCE(terms_version, 'v1-legacy')
 WHERE status IN ('approved','active')
   AND terms_accepted_at IS NULL;


-- ----- 3. Flip default + backfill pending rows ----------------------
ALTER TABLE public.sellers
  ALTER COLUMN status SET DEFAULT 'approved';

-- Old applicants stuck on 'pending' for review go live too — the
-- admin had no SLA on that queue and the user's pivot says we
-- trust members to abide by the code of conduct.
UPDATE public.sellers
   SET status            = 'approved',
       approved_at       = COALESCE(approved_at, NOW()),
       terms_accepted_at = COALESCE(terms_accepted_at, NOW()),
       terms_version     = COALESCE(terms_version, 'v1-legacy')
 WHERE status = 'pending';


-- ----- 4. Constraint: terms must be accepted to be live -------------
ALTER TABLE public.sellers
  DROP CONSTRAINT IF EXISTS sellers_terms_accepted_chk;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_terms_accepted_chk
  CHECK (
    status IN ('rejected','banned','pending')
    OR terms_accepted_at IS NOT NULL
  );


-- ----- 5. Index for the marketplace listing query -------------------
CREATE INDEX IF NOT EXISTS idx_sellers_active_approved
  ON public.sellers (is_active, status)
  WHERE is_active = TRUE AND status = 'approved';
