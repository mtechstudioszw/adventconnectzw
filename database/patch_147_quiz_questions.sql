-- patch_147: Bible Quiz (Adventist doctrine). Admin-curated questions, read by
-- all members. Streaks/scores are local for the MVP (no leaderboard yet).
CREATE TABLE IF NOT EXISTS public.quiz_questions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  question      text NOT NULL,
  options       jsonb NOT NULL,                 -- ["A","B","C","D"]
  correct_index int  NOT NULL CHECK (correct_index BETWEEN 0 AND 3),
  explanation   text,
  reference     text,                            -- Bible / SoP reference
  category      text NOT NULL DEFAULT 'General',
  difficulty    text NOT NULL DEFAULT 'medium'
                  CHECK (difficulty IN ('easy','medium','hard')),
  is_published  boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.quiz_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS quiz_read ON public.quiz_questions;
CREATE POLICY quiz_read ON public.quiz_questions
  FOR SELECT TO authenticated USING (is_published);

DROP POLICY IF EXISTS quiz_admin_write ON public.quiz_questions;
CREATE POLICY quiz_admin_write ON public.quiz_questions
  FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.quiz_questions TO authenticated;
