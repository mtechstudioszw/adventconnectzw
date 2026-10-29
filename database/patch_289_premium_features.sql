-- =====================================================================
--  PATCH 289 — Premium: Business tier, gold-tick verification, boosts
--  STATUS: not yet applied
--
--  Owner, 29 Oct 2026: "We need to start making money with this thing …
--  the first premium feature which is basic is getting a verified golden
--  tick … ranking of your store … products to be at the top … jobs".
--  Android only for now; the app hides every entry point on iOS
--  (kHidePayments) — nothing here is platform-specific.
--
--  THE LEVELS (one Play product `premium_monthly`, base plans — see
--  lib/services/billing/premium_tier.dart for why it is one product):
--    plus      `monthly`           US$3/mo   no ads, gold tick*, calls, AI
--    pro       `pro-monthly`       US$5/mo   + more AI and calls
--              `annualpermanent`   US$30/yr
--    business  `business-monthly`  US$10/mo  + featured shop, 4 listing
--                                            boosts and 2 featured jobs a
--                                            month, gold tick on a Page*
--    (* only after an ID check a super admin approves)
--
--  ONE-OFF BOOSTS (Play one-time products, verified by the verify-boost
--  edge function, which calls grant_boost() below with the service role):
--    boost_listing_7d   US$1  a listing in Marketplace's Featured row, 7 days
--    boost_job_14d      US$2  a job pinned in Jobs as Featured, 14 days
--
--  RULES THIS PATCH KEEPS
--    * Money is only ever turned into perks by the server: by
--      sync_premium_until() (from verified store state) and grant_boost()
--      (from verify-boost, or a Business credit). No client write can set
--      a tick, a featured flag or a featured_until — every guard below
--      snaps them back unless the server's own transaction flag is on.
--    * Paid placement is LABELLED in the app ("Promoted"), never mixed
--      into the organic ranking (lib/services/market_ranking.dart).
--    * featured_until NULL = set by the marketplace team by hand (left
--      alone); non-NULL = paid, and it expires by itself (cron below).
--    * ID documents live in a PRIVATE bucket, readable only by their owner
--      and super admins, and the app deletes them once a decision is made.
--
--  CLAUDE.md checklist
--    1. No new profiles column. is_verified already exists and is already
--       snapped back by profiles_block_privilege_self_grant().
--    2. No new grants on profiles.
--    3. n/a.
--    4. New BEFORE triggers are INSERT/UPDATE only; every one still
--       returns COALESCE(NEW, OLD).
--    The products, jobs and sellers guards are re-stated IN FULL from the
--    live definitions (read 29 Oct 2026), with the new columns added.
-- =====================================================================

BEGIN;

-- =====================================================================
--  1. The Business tier
-- =====================================================================

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_premium_tier_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_premium_tier_check
  CHECK (premium_tier IS NULL OR premium_tier IN ('plus', 'pro', 'business'));

CREATE OR REPLACE FUNCTION public.premium_tier_for_base_plan(p_plan text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_plan = 'business-monthly' THEN 'business'
    -- 'annualpermanent' is the yearly plan's real id (patch 288).
    WHEN p_plan IN ('pro-monthly', 'annualpermanent', 'annual') THEN 'pro'
    -- Everything else, INCLUDING NULL, is the lowest paid tier, so an
    -- unrecognised plan under-grants rather than over-grants.
    ELSE 'plus'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.premium_tier_rank(p_tier text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE p_tier
    WHEN 'business' THEN 3
    WHEN 'pro' THEN 2
    WHEN 'plus' THEN 1
    ELSE 0
  END;
$function$;

-- =====================================================================
--  2. Gold-tick verification requests
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.verification_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- 'person' = the member's own gold tick; 'page' = a Page they created.
  kind          text NOT NULL DEFAULT 'person' CHECK (kind IN ('person', 'page')),
  page_id       uuid REFERENCES public.pages(id) ON DELETE CASCADE,
  legal_name    text NOT NULL CHECK (char_length(trim(legal_name)) BETWEEN 2 AND 120),
  -- What the tick says about them: 'pastor', 'ministry', 'musician',
  -- 'business', 'public_figure', 'member'. Free text is not offered.
  category      text NOT NULL DEFAULT 'member'
                CHECK (category IN ('member', 'pastor', 'ministry', 'musician',
                                    'business', 'public_figure')),
  -- Paths in the private `verification_docs` bucket, "<uid>/<file>".
  -- Cleared when a decision is made (the files are deleted then too).
  id_doc_path   text,
  selfie_path   text,
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected', 'revoked')),
  reason        text,
  reviewed_by   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verification_page_needs_id
    CHECK ((kind = 'page') = (page_id IS NOT NULL))
);

-- One open (pending or approved) request per member, or per Page.
CREATE UNIQUE INDEX IF NOT EXISTS verification_requests_one_open_person
  ON public.verification_requests (user_id)
  WHERE kind = 'person' AND status IN ('pending', 'approved');
CREATE UNIQUE INDEX IF NOT EXISTS verification_requests_one_open_page
  ON public.verification_requests (page_id)
  WHERE kind = 'page' AND status IN ('pending', 'approved');
CREATE INDEX IF NOT EXISTS verification_requests_status_idx
  ON public.verification_requests (status, created_at);

ALTER TABLE public.verification_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS verification_select ON public.verification_requests;
CREATE POLICY verification_select ON public.verification_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_super_admin());

DROP POLICY IF EXISTS verification_insert_self ON public.verification_requests;
CREATE POLICY verification_insert_self ON public.verification_requests
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- A member may withdraw a request that is still waiting.
DROP POLICY IF EXISTS verification_delete_pending ON public.verification_requests;
CREATE POLICY verification_delete_pending ON public.verification_requests
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');

REVOKE ALL ON public.verification_requests FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.verification_requests TO authenticated;
-- Deliberately no UPDATE: decisions go through review_verification().

-- Whatever a client sends, a new request starts pending and unreviewed.
CREATE OR REPLACE FUNCTION public.verification_requests_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  NEW.user_id     := auth.uid();
  NEW.status      := 'pending';
  NEW.reason      := NULL;
  NEW.reviewed_by := NULL;
  NEW.reviewed_at := NULL;
  NEW.created_at  := now();

  IF NEW.id_doc_path IS NULL OR NEW.selfie_path IS NULL
     OR split_part(NEW.id_doc_path, '/', 1) <> auth.uid()::text
     OR split_part(NEW.selfie_path, '/', 1) <> auth.uid()::text THEN
    RAISE EXCEPTION 'VERIFY_DOCS'
      USING ERRCODE = '22023',
            HINT = 'Add a photo of your ID and a selfie.';
  END IF;

  IF NEW.kind = 'page' AND NOT EXISTS (
       SELECT 1 FROM public.pages pg
        WHERE pg.id = NEW.page_id AND pg.created_by = auth.uid()) THEN
    RAISE EXCEPTION 'Only the person who created a Page can verify it.'
      USING ERRCODE = '42501';
  END IF;

  -- After a rejection, wait a week before trying again.
  IF EXISTS (
       SELECT 1 FROM public.verification_requests r
        WHERE r.user_id = auth.uid()
          AND r.kind = NEW.kind
          AND r.page_id IS NOT DISTINCT FROM NEW.page_id
          AND r.status = 'rejected'
          AND r.reviewed_at > now() - interval '7 days') THEN
    RAISE EXCEPTION 'VERIFY_COOLDOWN'
      USING ERRCODE = '42501',
            HINT = 'You can apply again 7 days after a decision.';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS verification_requests_guard_trg ON public.verification_requests;
CREATE TRIGGER verification_requests_guard_trg
  BEFORE INSERT ON public.verification_requests
  FOR EACH ROW EXECUTE FUNCTION public.verification_requests_guard();

-- The private bucket for ID photos and selfies -----------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('verification_docs', 'verification_docs', false, 8 * 1024 * 1024,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS verification_docs_insert_own ON storage.objects;
CREATE POLICY verification_docs_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verification_docs'
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS verification_docs_select ON storage.objects;
CREATE POLICY verification_docs_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text
              OR public.is_super_admin()));

DROP POLICY IF EXISTS verification_docs_delete ON storage.objects;
CREATE POLICY verification_docs_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'verification_docs'
         AND ((storage.foldername(name))[1] = auth.uid()::text
              OR public.is_super_admin()));

-- =====================================================================
--  3. refresh_paid_perks — the one place perks follow the plan
--
--  Called by sync_premium_until() (service role, after every verified
--  store change), by review_verification() (a super admin), and hourly
--  by cron. Never by a member: EXECUTE is revoked below. Every caller is
--  either JWT-less or a super admin, so the table guards let it write.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.refresh_paid_perks(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tier   text;
  v_until  timestamptz;
  v_super  boolean;
  v_latest text;
BEGIN
  SELECT CASE WHEN p.premium_until > now()
              THEN COALESCE(p.premium_tier, 'plus') END,
         p.premium_until,
         COALESCE(p.is_super_admin, false)
    INTO v_tier, v_until, v_super
    FROM public.profiles p
   WHERE p.id = p_user;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- The member's own tick: approved ID check AND any paid level.
  -- (The official team account keeps its tick as a super admin.)
  -- Members who never applied are left exactly as they are.
  SELECT r.status INTO v_latest
    FROM public.verification_requests r
   WHERE r.user_id = p_user AND r.kind = 'person'
   ORDER BY (r.status = 'approved') DESC, r.created_at DESC
   LIMIT 1;

  IF v_latest = 'approved' THEN
    UPDATE public.profiles
       SET is_verified = (v_tier IS NOT NULL OR v_super)
     WHERE id = p_user
       AND is_verified IS DISTINCT FROM (v_tier IS NOT NULL OR v_super);
  ELSIF v_latest = 'revoked' THEN
    UPDATE public.profiles SET is_verified = false
     WHERE id = p_user AND is_verified;
  END IF;

  -- Page ticks: approved ID check AND the creator holds Business.
  UPDATE public.pages pg
     SET is_verified = (v_tier = 'business' OR v_super)
    FROM public.verification_requests r
   WHERE r.user_id = p_user AND r.kind = 'page' AND r.status = 'approved'
     AND pg.id = r.page_id
     AND pg.is_verified IS DISTINCT FROM (v_tier = 'business' OR v_super);

  UPDATE public.pages pg
     SET is_verified = false
    FROM public.verification_requests r
   WHERE r.user_id = p_user AND r.kind = 'page' AND r.status = 'revoked'
     AND pg.id = r.page_id AND pg.is_verified
     AND NOT EXISTS (SELECT 1 FROM public.verification_requests a
                      WHERE a.page_id = r.page_id AND a.status = 'approved');

  -- Business: the member's approved shop is a Featured store for as
  -- long as the plan runs. Hand-featured shops (featured_until NULL)
  -- are never touched.
  IF v_tier = 'business' THEN
    UPDATE public.sellers
       SET featured = true, featured_until = v_until
     WHERE auth_user_id = p_user AND status = 'approved'
       AND (featured IS DISTINCT FROM true
            OR featured_until IS DISTINCT FROM v_until);
  ELSE
    UPDATE public.sellers
       SET featured = false, featured_until = NULL
     WHERE auth_user_id = p_user AND featured_until IS NOT NULL;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_paid_perks(uuid) FROM PUBLIC, anon, authenticated;

-- sync_premium_until: Business ranks first, then perks follow ----------
CREATE OR REPLACE FUNCTION public.sync_premium_until(p_user uuid)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_until TIMESTAMPTZ;
  v_tier  TEXT;
BEGIN
  -- Statuses that keep access: active, in_grace (Google is retrying the
  -- card and asks that access continue), cancelled (auto-renew off, the
  -- period is paid for). Everything else grants nothing.
  --
  -- The BEST tier among entitling rows, then the latest date within it,
  -- so the tier belongs to a row that is really in force.
  SELECT public.premium_tier_for_base_plan(s.base_plan_id)
    INTO v_tier
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL
   ORDER BY public.premium_tier_rank(
              public.premium_tier_for_base_plan(s.base_plan_id)) DESC,
            s.current_period_end DESC
   LIMIT 1;

  -- The date is the MAX across every entitling row: a member must not
  -- lose paid-for days because the best tier expires first.
  SELECT MAX(s.current_period_end)
    INTO v_until
    FROM public.subscriptions s
   WHERE s.user_id = p_user
     AND s.status IN ('active', 'in_grace', 'cancelled')
     AND s.current_period_end IS NOT NULL;

  UPDATE public.profiles
     SET premium_until = v_until,
         premium_tier  = CASE WHEN v_until IS NULL THEN NULL ELSE v_tier END
   WHERE id = p_user;

  PERFORM public.refresh_paid_perks(p_user);

  RETURN v_until;
END;
$function$;

-- review_verification — a super admin decides --------------------------
CREATE OR REPLACE FUNCTION public.review_verification(
  p_id uuid,
  p_action text,          -- 'approve' | 'reject' | 'revoke'
  p_reason text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_req public.verification_requests%ROWTYPE;
  v_status text;
  v_title text;
  v_body text;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Only a super admin can review verification.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req FROM public.verification_requests WHERE id = p_id
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such request.' USING ERRCODE = 'P0002';
  END IF;

  v_status := CASE p_action
    WHEN 'approve' THEN 'approved'
    WHEN 'reject'  THEN 'rejected'
    WHEN 'revoke'  THEN 'revoked'
  END;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Unknown action %', p_action USING ERRCODE = '22023';
  END IF;
  IF p_action IN ('approve', 'reject') AND v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'That request was already decided.' USING ERRCODE = '22023';
  END IF;
  IF p_action = 'revoke' AND v_req.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved tick can be revoked.' USING ERRCODE = '22023';
  END IF;
  IF p_action IN ('reject', 'revoke') AND COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Give the member a reason.' USING ERRCODE = '22023';
  END IF;

  -- The document paths are cleared here; the admin screen deletes the
  -- files themselves right after this returns.
  UPDATE public.verification_requests
     SET status = v_status,
         reason = NULLIF(trim(p_reason), ''),
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         id_doc_path = NULL,
         selfie_path = NULL
   WHERE id = p_id;

  PERFORM public.refresh_paid_perks(v_req.user_id);

  v_title := CASE v_status
    WHEN 'approved' THEN 'You''re verified'
    WHEN 'rejected' THEN 'Verification not approved'
    ELSE 'Verification removed' END;
  v_body := CASE v_status
    WHEN 'approved' THEN
      'Your ID check passed. The gold tick shows while your Premium is active.'
    ELSE NULLIF(trim(p_reason), '') END;

  INSERT INTO public.notifications (user_id, title, body, type,
                                    reference_type, reference_id)
  VALUES (v_req.user_id, v_title, v_body, 'verification',
          'verification_request', v_req.id::text);

  RETURN v_status;
END;
$function$;

REVOKE ALL ON FUNCTION public.review_verification(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_verification(uuid, text, text) TO authenticated;

-- =====================================================================
--  4. Boosts
-- =====================================================================

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS featured_until timestamptz;
ALTER TABLE public.jobs     ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false;
ALTER TABLE public.jobs     ADD COLUMN IF NOT EXISTS featured_until timestamptz;
ALTER TABLE public.sellers  ADD COLUMN IF NOT EXISTS featured_until timestamptz;

CREATE TABLE IF NOT EXISTS public.boosts (
  id              bigserial PRIMARY KEY,
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_type     text NOT NULL CHECK (target_type IN ('product', 'job')),
  target_id       bigint NOT NULL,
  source          text NOT NULL CHECK (source IN ('purchase', 'credit', 'admin')),
  -- Play purchase token for a bought boost; one token, one boost.
  purchase_token  text UNIQUE,
  order_id        text,
  days            integer NOT NULL CHECK (days BETWEEN 1 AND 60),
  ends_at         timestamptz NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boosts_user_month_idx
  ON public.boosts (user_id, source, target_type, created_at);
CREATE INDEX IF NOT EXISTS boosts_target_idx
  ON public.boosts (target_type, target_id, ends_at);

ALTER TABLE public.boosts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS boosts_select ON public.boosts;
CREATE POLICY boosts_select ON public.boosts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_super_admin());
REVOKE ALL ON public.boosts FROM anon, authenticated;
GRANT SELECT ON public.boosts TO authenticated;
-- Rows are written only by grant_boost().

-- The guards, re-stated in full with the new columns -------------------

CREATE OR REPLACE FUNCTION public.products_guard_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.is_featured := false;
    NEW.featured_until := NULL;
    NEW.view_count := 0;
  ELSE
    -- grant_boost (patch 289) is the one member-session writer allowed
    -- to feature a listing; it marks its own transaction.
    IF COALESCE(current_setting('app.granting_boost', true), '') <> 'on' THEN
      NEW.is_featured := OLD.is_featured;
      NEW.featured_until := OLD.featured_until;
    END IF;
    -- record_product_view (patch_277) is the one writer allowed to move
    -- view_count; it marks its own transaction.
    IF COALESCE(current_setting('app.recording_view', true), '') <> 'on' THEN
      NEW.view_count := OLD.view_count;
    END IF;
    NEW.seller_id := OLD.seller_id;
    NEW.created_at := OLD.created_at;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.jobs_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ok boolean;
BEGIN
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Linking a company Page needs to be one of its admins.
  IF NEW.page_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.page_id IS DISTINCT FROM OLD.page_id)
     AND NOT public.can_edit_page(NEW.page_id) THEN
    RAISE EXCEPTION 'Only an admin of that Page can post jobs for it.'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.expires_at := now() + interval '30 days';
    NEW.poster_id := auth.uid();
    NEW.is_featured := false;        -- patch 289
    NEW.featured_until := NULL;      -- patch 289
    RETURN COALESCE(NEW, OLD);
  END IF;

  NEW.poster_id := OLD.poster_id;
  NEW.created_at := OLD.created_at;

  -- patch 289: only grant_boost may feature a job.
  IF COALESCE(current_setting('app.granting_boost', true), '') <> 'on' THEN
    NEW.is_featured := OLD.is_featured;
    NEW.featured_until := OLD.featured_until;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_ok := (OLD.status = 'open'   AND NEW.status IN ('filled', 'closed'))
         OR (OLD.status = 'filled' AND NEW.status = 'open')
         -- renew_job: expired → open with a fresh 30 days
         OR (OLD.status = 'expired' AND NEW.status = 'open'
             AND NEW.expires_at BETWEEN now() + interval '29 days'
                                    AND now() + interval '31 days');
    IF NOT v_ok THEN
      NEW.status := OLD.status;
    END IF;
  END IF;

  -- Expiry only moves by renewing (a fresh 30 days), never further.
  IF NEW.expires_at IS DISTINCT FROM OLD.expires_at
     AND NOT (NEW.expires_at BETWEEN now() + interval '29 days'
                                 AND now() + interval '31 days') THEN
    NEW.expires_at := OLD.expires_at;
  END IF;

  -- A live listing whose identity changes goes back for review.
  IF OLD.status = 'open' AND NEW.status = 'open' AND (
       NEW.title IS DISTINCT FROM OLD.title
    OR NEW.company IS DISTINCT FROM OLD.company
    OR NEW.contact_phone IS DISTINCT FROM OLD.contact_phone
    OR NEW.contact_email IS DISTINCT FROM OLD.contact_email
    OR NEW.apply_url IS DISTINCT FROM OLD.apply_url
    OR NEW.salary_range IS DISTINCT FROM OLD.salary_range
    OR NEW.pay_min IS DISTINCT FROM OLD.pay_min
    OR NEW.pay_max IS DISTINCT FROM OLD.pay_max
    OR NEW.page_id IS DISTINCT FROM OLD.page_id) THEN
    NEW.status := 'pending';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sellers_guard_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
    NEW.featured_until := NULL;      -- patch 289
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
  NEW.featured_until := OLD.featured_until;   -- patch 289
  NEW.approved_at := OLD.approved_at;

  -- Always the truth from seller_ratings, whoever is writing.
  SELECT count(*), COALESCE(avg(r.rating)::decimal(3,2), 0)
    INTO NEW.rating_count, NEW.rating
    FROM public.seller_ratings r
   WHERE r.seller_id = OLD.id;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- grant_boost — the one writer of a paid boost -------------------------
--
-- Called by verify-boost (service role) for a bought boost, and by
-- use_boost_credit() for a Business credit. Idempotent on the purchase
-- token, so Play replaying a purchase never stacks a second boost.
CREATE OR REPLACE FUNCTION public.grant_boost(
  p_user uuid,
  p_target_type text,
  p_target_id bigint,
  p_days integer,
  p_source text,
  p_token text DEFAULT NULL,
  p_order text DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ends timestamptz;
  v_owner uuid;
  v_live boolean;
  v_current timestamptz;
BEGIN
  IF p_token IS NOT NULL THEN
    SELECT ends_at INTO v_ends FROM public.boosts WHERE purchase_token = p_token;
    IF FOUND THEN
      RETURN v_ends;
    END IF;
  END IF;

  IF p_target_type = 'product' THEN
    SELECT seller_id, status = 'available' AND moderation_hidden_at IS NULL,
           featured_until
      INTO v_owner, v_live, v_current
      FROM public.products WHERE id = p_target_id;
  ELSIF p_target_type = 'job' THEN
    SELECT poster_id, status = 'open' AND expires_at > now(),
           featured_until
      INTO v_owner, v_live, v_current
      FROM public.jobs WHERE id = p_target_id;
  ELSE
    RAISE EXCEPTION 'BOOST_TARGET' USING ERRCODE = '22023';
  END IF;

  IF v_owner IS NULL OR v_owner <> p_user THEN
    RAISE EXCEPTION 'BOOST_NOT_OWNER'
      USING ERRCODE = '42501', HINT = 'You can only boost your own listings.';
  END IF;
  IF NOT v_live THEN
    RAISE EXCEPTION 'BOOST_NOT_LIVE'
      USING ERRCODE = '22023', HINT = 'Only a live listing can be boosted.';
  END IF;

  -- Boosting again extends from the current end, never overlaps.
  v_ends := GREATEST(COALESCE(v_current, now()), now())
            + make_interval(days => p_days);

  PERFORM set_config('app.granting_boost', 'on', true);
  IF p_target_type = 'product' THEN
    UPDATE public.products
       SET is_featured = true, featured_until = v_ends
     WHERE id = p_target_id;
  ELSE
    UPDATE public.jobs
       SET is_featured = true, featured_until = v_ends
     WHERE id = p_target_id;
  END IF;
  PERFORM set_config('app.granting_boost', 'off', true);

  INSERT INTO public.boosts (user_id, target_type, target_id, source,
                             purchase_token, order_id, days, ends_at)
  VALUES (p_user, p_target_type, p_target_id, p_source,
          p_token, p_order, p_days, v_ends);

  RETURN v_ends;
END;
$function$;

REVOKE ALL ON FUNCTION public.grant_boost(uuid, text, bigint, integer, text, text, text)
  FROM PUBLIC, anon, authenticated;

-- Business credits ------------------------------------------------------
--
-- Mirrors BoostCatalog in lib/services/billing/boost_catalog.dart.
CREATE OR REPLACE FUNCTION public.boost_credit_allowance(p_target_type text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE p_target_type WHEN 'product' THEN 4 WHEN 'job' THEN 2 ELSE 0 END;
$function$;

CREATE OR REPLACE FUNCTION public.boost_credits_left()
RETURNS TABLE (product_left integer, job_left integer, resets_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH me AS (
    SELECT (p.premium_until > now() AND p.premium_tier = 'business') AS biz
      FROM public.profiles p WHERE p.id = auth.uid()
  ), used AS (
    SELECT target_type, count(*)::int n
      FROM public.boosts
     WHERE user_id = auth.uid() AND source = 'credit'
       AND created_at >= date_trunc('month', now())
     GROUP BY target_type
  )
  SELECT
    CASE WHEN COALESCE((SELECT biz FROM me), false)
         THEN GREATEST(public.boost_credit_allowance('product')
              - COALESCE((SELECT n FROM used WHERE target_type = 'product'), 0), 0)
         ELSE 0 END,
    CASE WHEN COALESCE((SELECT biz FROM me), false)
         THEN GREATEST(public.boost_credit_allowance('job')
              - COALESCE((SELECT n FROM used WHERE target_type = 'job'), 0), 0)
         ELSE 0 END,
    date_trunc('month', now()) + interval '1 month';
$function$;

REVOKE ALL ON FUNCTION public.boost_credits_left() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.boost_credits_left() TO authenticated;

CREATE OR REPLACE FUNCTION public.use_boost_credit(
  p_target_type text,
  p_target_id bigint
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_used integer;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles
                  WHERE id = v_me AND premium_until > now()
                    AND premium_tier = 'business') THEN
    RAISE EXCEPTION 'BOOST_NEEDS_BUSINESS'
      USING ERRCODE = '42501', HINT = 'Monthly boosts come with Business.';
  END IF;

  -- Serialise this member's credit spends so two taps can't both pass.
  PERFORM pg_advisory_xact_lock(hashtext('boost_credit:' || v_me::text));

  SELECT count(*) INTO v_used
    FROM public.boosts
   WHERE user_id = v_me AND source = 'credit'
     AND target_type = p_target_type
     AND created_at >= date_trunc('month', now());

  IF v_used >= public.boost_credit_allowance(p_target_type) THEN
    RAISE EXCEPTION 'BOOST_NO_CREDITS'
      USING ERRCODE = '42501', HINT = 'This month''s boosts are used up.';
  END IF;

  RETURN public.grant_boost(
    v_me, p_target_type, p_target_id,
    CASE p_target_type WHEN 'job' THEN 14 ELSE 7 END,
    'credit');
END;
$function$;

REVOKE ALL ON FUNCTION public.use_boost_credit(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.use_boost_credit(text, bigint) TO authenticated;

-- =====================================================================
--  5. Hourly: paid things end on time
-- =====================================================================

CREATE OR REPLACE FUNCTION public.expire_paid_perks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.products SET is_featured = false
   WHERE is_featured AND featured_until IS NOT NULL AND featured_until < now();
  UPDATE public.jobs SET is_featured = false
   WHERE is_featured AND featured_until IS NOT NULL AND featured_until < now();
  UPDATE public.sellers SET featured = false, featured_until = NULL
   WHERE featured_until IS NOT NULL AND featured_until < now();

  -- Ticks follow lapsed plans even when no store event arrives.
  PERFORM public.refresh_paid_perks(u.user_id)
     FROM (SELECT DISTINCT user_id FROM public.verification_requests
            WHERE status IN ('approved', 'revoked')) u;
END;
$function$;

REVOKE ALL ON FUNCTION public.expire_paid_perks() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire-paid-perks';
SELECT cron.schedule('expire-paid-perks', '7 * * * *',
                     $$SELECT public.expire_paid_perks()$$);

-- =====================================================================
--  6. Allowances follow the level that was paid for
--
--  Found while adding Business: the call caps knew only 'pro' and
--  'plus', so a Business member would have fallen through to the FREE
--  cap. And ai_sync_allowance gave every paid level the full 500
--  questions, while the paywall (TierBenefits) promises Plus 100. Nobody
--  holds a paid level today, so nobody loses anything by this.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.call_daily_cap_seconds(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT (CASE
    WHEN public.call_premium_tier(p_user) IN ('pro', 'business')
      THEN public.call_cfg_int('call.pro_daily_minutes',  720)
    WHEN public.call_premium_tier(p_user) = 'plus'
      THEN public.call_cfg_int('call.plus_daily_minutes', 360)
    ELSE public.call_cfg_int('call.free_daily_minutes', 120)
  END) * 60;
$function$;

CREATE OR REPLACE FUNCTION public.call_monthly_cap_seconds(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT (CASE
    WHEN public.call_premium_tier(p_user) IN ('pro', 'business')
      THEN public.call_cfg_int('call.pro_monthly_minutes',  9000)
    WHEN public.call_premium_tier(p_user) = 'plus'
      THEN public.call_cfg_int('call.plus_monthly_minutes', 4500)
    ELSE public.call_cfg_int('call.free_monthly_minutes', 1500)
  END) * 60;
$function$;

CREATE OR REPLACE FUNCTION public.ai_sync_allowance(p_user uuid)
RETURNS public.ai_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row     public.ai_accounts;
  v_period  DATE := date_trunc('month', NOW() AT TIME ZONE 'utc')::DATE;
  v_units   INTEGER;
  v_free    INTEGER;
BEGIN
  SELECT * INTO v_row FROM public.ai_accounts WHERE user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- ---- Free refill, for everybody ----------------------------------
  --
  -- Guarded on the global pool: a closed pool must not mint units. The
  -- member simply refills the next time they are synced after it
  -- reopens, which is correct — the pool being shut is exactly the
  -- state in which we do not want to promise more free usage.
  IF v_row.free_period IS DISTINCT FROM v_period
     AND public.ai_free_pool_open()
  THEN
    v_free := public.ai_config_int('ai_free_grant_units', 10)::INTEGER;

    UPDATE public.ai_accounts
       SET free_units_granted = v_free,
           free_units_spent   = 0,
           free_period        = v_period
     WHERE user_id = p_user
    RETURNING * INTO v_row;

    -- 'free_grant', not 'grant' — ai_ledger_kind_chk allows only
    -- free_grant/allowance/spend/refund/adjust, so the obvious spelling
    -- fails the constraint on the first refill.
    INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
    VALUES (p_user, 'free_grant', v_free, 'free',
            'Free refill for ' || to_char(v_period, 'Mon YYYY'));
  END IF;

  -- ---- Premium allowance -------------------------------------------
  IF NOT public.ai_is_premium(p_user) THEN
    IF v_row.allowance_units <> 0 OR v_row.allowance_spent <> 0 THEN
      UPDATE public.ai_accounts
         SET allowance_units = 0, allowance_spent = 0, allowance_period = NULL
       WHERE user_id = p_user
      RETURNING * INTO v_row;
    END IF;
    RETURN v_row;
  END IF;

  IF v_row.allowance_period IS DISTINCT FROM v_period THEN
    -- patch 289: Plus gets the Plus allowance; Pro and Business the full.
    v_units := CASE public.call_premium_tier(p_user)
      WHEN 'plus' THEN public.ai_config_int('ai_plus_monthly_units', 100)
      ELSE public.ai_config_int('ai_premium_monthly_units', 500)
    END::INTEGER;

    UPDATE public.ai_accounts
       SET allowance_units = v_units,
           allowance_spent = 0,
           allowance_period = v_period
     WHERE user_id = p_user
    RETURNING * INTO v_row;

    INSERT INTO public.ai_ledger (user_id, kind, units, pool, note)
    VALUES (p_user, 'allowance', v_units, 'allowance',
            'Premium allowance for ' || to_char(v_period, 'Mon YYYY'));
  END IF;

  RETURN v_row;
END;
$function$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ---------------------------------------------------------------------
--  Check it worked (read-only). Expect: business, 4, 2, a schedule,
--  verification_docs private (false).
-- ---------------------------------------------------------------------
-- SELECT public.premium_tier_for_base_plan('business-monthly') AS biz,
--        public.boost_credit_allowance('product') AS listing_credits,
--        public.boost_credit_allowance('job') AS job_credits,
--        (SELECT schedule FROM cron.job WHERE jobname = 'expire-paid-perks') AS cron,
--        (SELECT public FROM storage.buckets WHERE id = 'verification_docs') AS docs_public;
