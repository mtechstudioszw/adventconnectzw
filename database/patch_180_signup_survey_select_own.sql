-- =====================================================================
--  PATCH 180 — let members read their OWN signup survey row
--
--  THE BUG: `signup_surveys` had exactly one SELECT policy —
--  `signup_surveys_admin_read`, gated on is_super_admin(). Members could
--  INSERT but never SELECT, not even their own answer.
--
--  The app submits with PostgREST upsert (ON CONFLICT DO UPDATE), and
--  that path RETURNS the row. Under RLS, INSERT ... RETURNING also has to
--  satisfy a SELECT policy — so every submission by a normal member
--  failed with:
--
--      42501: new row violates row-level security policy
--
--  Proof, run against production before this patch (as a normal member):
--      insert ... ;            -- succeeds
--      insert ... RETURNING id; -- 42501
--
--  So the answers never landed. 164 members, one survey row: the
--  founder's, which saved only because the founder IS the super admin and
--  therefore the only account the SELECT policy admitted. That is exactly
--  the reported "users submit but nothing reaches the admin dashboard".
--
--  The client made it permanent: it wrote its "already asked" flag BEFORE
--  the network call, so the prompt never came back to try again. Fixed in
--  SignupSurveyService alongside this.
--
--  A member reading the answer they themselves gave is not a disclosure —
--  and it is what makes the write work at all.
-- =====================================================================

DROP POLICY IF EXISTS signup_surveys_select_own ON public.signup_surveys;
CREATE POLICY signup_surveys_select_own ON public.signup_surveys
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

COMMENT ON POLICY signup_surveys_select_own ON public.signup_surveys IS
  'Members read their own row. Required for the upsert RETURNING path to '
  'pass RLS — without it every non-admin submission raised 42501.';
