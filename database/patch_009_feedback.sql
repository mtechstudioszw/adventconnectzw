-- =====================================================================
--  PATCH 009 — In-app feedback form
--
--  WHY:  Beta testers need a one-tap way to send bug reports and
--        feature requests without leaving the app. Until the web
--        admin dashboard ships, the team reads this table directly
--        in Supabase Studio (Database → Tables → feedback).
--
--  TABLE: public.feedback
--    Captures the submitter, what they said, what build they were on,
--    and a status field the team flips as items get triaged/resolved.
--
--  RLS:   submitters can INSERT their own rows (gated by user_is_active
--         so banned users can't spam). Only the submitter can SELECT
--         their own row (so they can see their submission history if
--         we ever add that surface). Service-role bypasses RLS for the
--         triage workflow.
--
--  PREREQUISITES: schema.sql + patch_001..patch_008 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


CREATE TABLE IF NOT EXISTS public.feedback (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category      TEXT NOT NULL DEFAULT 'general'
                  CHECK (category IN ('general','bug','feature_request','content','other')),
  subject       TEXT NOT NULL CHECK (char_length(subject) BETWEEN 3 AND 120),
  body          TEXT NOT NULL CHECK (char_length(body) BETWEEN 5 AND 2000),
  app_version   TEXT,
  platform      TEXT,
  status        TEXT NOT NULL DEFAULT 'new'
                  CHECK (status IN ('new','triaged','in_progress','resolved','wont_fix')),
  triaged_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  triaged_at    TIMESTAMPTZ,
  resolution_note TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_user_id ON public.feedback (user_id);
CREATE INDEX IF NOT EXISTS idx_feedback_status  ON public.feedback (status, created_at DESC);


ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;


DROP POLICY IF EXISTS "feedback_insert_self" ON public.feedback;
DROP POLICY IF EXISTS "feedback_select_self" ON public.feedback;

CREATE POLICY "feedback_insert_self" ON public.feedback
  FOR INSERT WITH CHECK (
    auth.uid() = user_id AND public.user_is_active()
  );

CREATE POLICY "feedback_select_self" ON public.feedback
  FOR SELECT USING (auth.uid() = user_id);


-- =====================================================================
--  END OF PATCH 009
-- =====================================================================
