-- =====================================================================
--  PATCH 126 — create the profile row only AFTER email verification
--
--  Bug (#10): on_auth_user_created (patch_001) fired AFTER INSERT on
--  auth.users, so a profile row was created the instant someone tapped
--  "Sign up" — before they verified their email. A user who abandons
--  signup left a permanent orphan profile.
--
--  Fix: gate the insert on email_confirmed_at and fire the trigger on the
--  confirmation UPDATE as well as INSERT.
--    * Email/password signup → email_confirmed_at is NULL at INSERT, so no
--      profile yet. When the user verifies, Supabase sets email_confirmed_at
--      (an UPDATE) → the trigger fires and the profile is created.
--    * Google / Apple / any auto-confirmed signup → email_confirmed_at is
--      already set at INSERT, so the profile is still created immediately.
--
--  The app only writes profile data in profile_setup, which runs AFTER
--  verification, so nothing depends on the row existing earlier.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  birth_text  TEXT := NEW.raw_user_meta_data->>'birth_date';
  birth_value DATE;
BEGIN
  -- Don't materialise a profile until the email is verified. OAuth/social
  -- users arrive already-confirmed so they're unaffected.
  IF NEW.email_confirmed_at IS NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    birth_value := birth_text::TIMESTAMPTZ::DATE;
  EXCEPTION WHEN OTHERS THEN
    birth_value := NULL;
  END;

  INSERT INTO public.profiles (id, full_name, date_of_birth)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    birth_value
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- Fire on INSERT (covers already-confirmed OAuth users) AND on the
-- email_confirmed_at UPDATE (covers email/password verification).
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT OR UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
