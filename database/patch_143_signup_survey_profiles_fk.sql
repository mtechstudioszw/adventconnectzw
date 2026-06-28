-- patch_143: fix User Insights "Could not find a relationship between
-- signup_surveys and profiles" (PGRST200). The embed profiles(full_name) needs
-- a FK from signup_surveys to public.profiles. user_id already FKs auth.users;
-- add a parallel FK to profiles (profiles.id == auth.users.id) so PostgREST can
-- resolve the join. Fixes both the in-app and web admin insights.
ALTER TABLE public.signup_surveys
  DROP CONSTRAINT IF EXISTS signup_surveys_user_profile_fkey;
ALTER TABLE public.signup_surveys
  ADD CONSTRAINT signup_surveys_user_profile_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
-- Nudge PostgREST to reload its schema cache so the new relationship is seen.
NOTIFY pgrst, 'reload schema';
