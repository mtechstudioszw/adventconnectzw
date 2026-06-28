-- patch_136: first-run signup survey ("how did you hear about us" + a short
-- question) so the founder can understand where users come from. One row per
-- user. Readable only by the super admin (for the admin insights view).

CREATE TABLE IF NOT EXISTS public.signup_surveys (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  source      text,
  answers     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.signup_surveys ENABLE ROW LEVEL SECURITY;

-- A user can write (and amend) only their own response.
DROP POLICY IF EXISTS signup_surveys_insert_own ON public.signup_surveys;
CREATE POLICY signup_surveys_insert_own ON public.signup_surveys
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS signup_surveys_update_own ON public.signup_surveys;
CREATE POLICY signup_surveys_update_own ON public.signup_surveys
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Only the super admin can read responses (powers the admin insights view).
DROP POLICY IF EXISTS signup_surveys_admin_read ON public.signup_surveys;
CREATE POLICY signup_surveys_admin_read ON public.signup_surveys
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

GRANT SELECT, INSERT, UPDATE ON public.signup_surveys TO authenticated;

-- Aggregated counts by source for the super-admin dashboard. Returns nothing
-- to non-admins.
CREATE OR REPLACE FUNCTION public.admin_survey_summary()
RETURNS TABLE(source text, total bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE(NULLIF(btrim(s.source), ''), 'Not specified') AS source,
         count(*)::bigint AS total
    FROM public.signup_surveys s
   WHERE public.is_super_admin()
   GROUP BY 1
   ORDER BY 2 DESC;
$$;

REVOKE ALL ON FUNCTION public.admin_survey_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_survey_summary() TO authenticated;
