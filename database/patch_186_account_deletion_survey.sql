-- patch_186 (#18): why people leave.
--
-- Asked on the way out of account deletion and surfaced in the web admin
-- dashboard. The whole value is in the aggregate, so the design point that
-- matters is that the row has to OUTLIVE the account it came from.
--
-- Hence NO foreign key to auth.users. An `ON DELETE CASCADE` would have
-- deleted every answer at the exact moment it became useful, and even
-- `ON DELETE SET NULL` would need the FK to exist while the delete-account
-- Edge Function is tearing the user down. `user_id` is a plain uuid kept
-- only so a support conversation can be matched to a reason; nothing joins
-- on it.

CREATE TABLE IF NOT EXISTS public.account_deletion_surveys (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Deliberately NOT a reference. See above.
  user_id    uuid,
  reason     text NOT NULL CHECK (btrim(reason) <> ''),
  detail     text CHECK (detail IS NULL OR char_length(detail) <= 500),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS account_deletion_surveys_recent_idx
  ON public.account_deletion_surveys (created_at DESC);

ALTER TABLE public.account_deletion_surveys ENABLE ROW LEVEL SECURITY;

-- Nobody reads this from the app — it is an admin aggregate.
REVOKE ALL ON public.account_deletion_surveys FROM authenticated, anon;

DROP POLICY IF EXISTS account_deletion_surveys_admin_read
  ON public.account_deletion_surveys;
CREATE POLICY account_deletion_surveys_admin_read
  ON public.account_deletion_surveys
  FOR SELECT TO authenticated
  USING (public.is_super_admin());
GRANT SELECT ON public.account_deletion_surveys TO authenticated;

-- Writing goes through an RPC rather than an INSERT policy.
--
-- Timing is the reason: this is submitted in the same breath as the account
-- is destroyed, and an INSERT policy checking `user_id = auth.uid()` would
-- start failing the instant the auth row went away. SECURITY DEFINER takes
-- the caller's id as it stands right now and does not care afterwards.
CREATE OR REPLACE FUNCTION public.account_deletion_survey_submit(
  p_reason text,
  p_detail text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF btrim(COALESCE(p_reason, '')) = '' THEN
    RETURN;  -- nothing to record; never block a deletion over a survey
  END IF;
  INSERT INTO public.account_deletion_surveys (user_id, reason, detail)
  VALUES (auth.uid(), btrim(p_reason), NULLIF(btrim(COALESCE(p_detail, '')), ''));
END;
$$;

REVOKE ALL ON FUNCTION public.account_deletion_survey_submit(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.account_deletion_survey_submit(text, text)
  TO authenticated;

-- What the admin console will chart: reasons, most common first.
CREATE OR REPLACE FUNCTION public.admin_deletion_reasons(p_days integer DEFAULT 90)
RETURNS TABLE (reason text, total bigint, share numeric)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH rows AS (
    SELECT s.reason
      FROM public.account_deletion_surveys s
     WHERE public.is_super_admin()
       AND s.created_at >= now() - make_interval(days => GREATEST(p_days, 1))
  )
  SELECT r.reason,
         COUNT(*)::bigint,
         ROUND(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM rows), 0), 1)
    FROM rows r
   GROUP BY r.reason
   ORDER BY 2 DESC;
$$;

REVOKE ALL ON FUNCTION public.admin_deletion_reasons(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_deletion_reasons(integer) TO authenticated;
