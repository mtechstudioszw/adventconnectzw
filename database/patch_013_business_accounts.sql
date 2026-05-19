-- =====================================================================
--  PATCH 013 — Personal vs Business accounts
--
--  WHY:  We want a clear Facebook-style distinction:
--          - Personal account (default)            → social usage only
--          - Business account (approved by admin)  → selling in the
--            marketplace + claiming a church
--
--        Users apply through the app. The app stores the application
--        and surfaces "pending" / "approved" / "rejected" to them. The
--        external admin panel (next pass) flips the actual
--        profiles.is_business switch when it approves an application.
--
--        Anyone whose application has not been approved cannot post
--        products or claim a church — those flows query this flag and
--        gate themselves accordingly. The existing account_type column
--        from schema.sql is left untouched for back-compat (we no
--        longer drive UI off it for personal/business mode).
--
--  PREREQUISITES: schema.sql + patch_001..patch_012 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- profiles.is_business — the live "am I a business?" switch.
-- Only admin / service role flips this. End users cannot.
-- ---------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_business BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_profiles_is_business
  ON public.profiles (is_business) WHERE is_business = TRUE;


-- ---------------------------------------------------------------------
-- business_applications — the form users submit to get approved.
-- One row per submission. A user may re-apply after a rejection but
-- only one pending row is allowed at a time.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.business_applications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  business_name   TEXT NOT NULL CHECK (char_length(business_name) BETWEEN 2 AND 80),
  category        TEXT NOT NULL CHECK (char_length(category) BETWEEN 2 AND 60),
  description     TEXT CHECK (description IS NULL OR char_length(description) <= 600),
  status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at     TIMESTAMPTZ,
  reviewer_note   TEXT
);

-- Enforce "one pending application per user". The partial unique index
-- only constrains rows where status = 'pending', so old approved /
-- rejected applications don't block re-application.
CREATE UNIQUE INDEX IF NOT EXISTS idx_business_apps_one_pending
  ON public.business_applications (user_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_business_apps_status
  ON public.business_applications (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_business_apps_user
  ON public.business_applications (user_id, created_at DESC);


ALTER TABLE public.business_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "biz_apps_select_self"    ON public.business_applications;
DROP POLICY IF EXISTS "biz_apps_insert_self"    ON public.business_applications;

-- Users see their own applications. The admin panel uses the service
-- role (which bypasses RLS) so it doesn't need a policy here.
CREATE POLICY "biz_apps_select_self" ON public.business_applications
  FOR SELECT USING (auth.uid() = user_id);

-- Users insert their own application in 'pending' state only.
-- user_is_active gates banned users out.
CREATE POLICY "biz_apps_insert_self" ON public.business_applications
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND status = 'pending'
    AND public.user_is_active()
  );

-- NOTE: there is intentionally no UPDATE / DELETE policy for end users.
-- All review flips happen via the admin panel (service role).


-- =====================================================================
--  END OF PATCH 013
-- =====================================================================
