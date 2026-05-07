-- =====================================================================
--  PATCH 001 — Auto-create profile rows on signup
--
--  WHY:  lib/services/auth_service.dart calls Supabase.auth.signUp() with
--        full_name and birth_date in user metadata. That writes only to
--        auth.users — there is no public.profiles row. Without one,
--        public.user_is_active() returns FALSE for the new user, every
--        write policy denies them, and any FK reference to profiles.id
--        from another table fails.
--
--  WHAT: One function (handle_new_user) and one trigger (on_auth_user_created)
--        that mirrors a new auth.users row into public.profiles using
--        full_name + birth_date from user metadata.
--
--  IDEMPOTENT: yes — safe to run multiple times. Existing rows are not
--              touched (ON CONFLICT DO NOTHING). The trigger drops and
--              re-creates itself.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  birth_text  TEXT := NEW.raw_user_meta_data->>'birth_date';
  birth_value DATE;
BEGIN
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =====================================================================
--  BACKFILL — give an existing auth.users a profile row if they don't
--  already have one. This catches anyone you signed up before the
--  trigger existed. Safe to run; it skips users who already have a row.
-- =====================================================================
INSERT INTO public.profiles (id, full_name, date_of_birth)
SELECT
  u.id,
  u.raw_user_meta_data->>'full_name'                 AS full_name,
  CASE
    WHEN u.raw_user_meta_data->>'birth_date' IS NOT NULL
      THEN (u.raw_user_meta_data->>'birth_date')::TIMESTAMPTZ::DATE
    ELSE NULL
  END                                                AS date_of_birth
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;
