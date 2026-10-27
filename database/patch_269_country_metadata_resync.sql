-- =====================================================================
--  PATCH 269 — re-sync auth metadata country from the profiles row
--
--  Bug fixed in the app on 27 Oct 2026 (AuthService.updateProfile).
--
--  The app wrote `country` to auth metadata (auth.users.raw_user_meta_data)
--  BEFORE writing the profiles row. When trg_country_change_cooldown
--  (patch_215/221) rejected the row update, the member saw "You can only
--  change your country once every 2 weeks" — but metadata already held the
--  rejected country. Every screen reading metadata
--  (AuthService.currentCountry(): Marketplace, Events, Jobs, Sabbath timer,
--  profile header) then disagreed with everything reading the row.
--
--  The app fix stops new drift. This repairs the members it already hit.
--
--  SOURCE OF TRUTH: public.profiles.country — the trigger guards it, so it
--  only ever holds an accepted value. Metadata is a mirror.
--
--  Touches ONE key in raw_user_meta_data; every other key is preserved
--  (jsonb `||` merge). Does not touch profiles, country_changed_at, or any
--  cooldown. Idempotent: a second run updates 0 rows.
--
--  Members pick up the corrected value on their next token refresh
--  (≤ 1 hour) or sign-in — user_metadata travels in the session JWT.
--
--  CLAUDE.md checklist: no new column, no new trigger, no grant change.
-- =====================================================================

-- ---- 1. PREVIEW — run this first and read it -------------------------
-- SELECT u.id,
--        u.raw_user_meta_data->>'country' AS metadata_country,
--        p.country                         AS row_country,
--        p.country_changed_at
--   FROM auth.users u
--   JOIN public.profiles p ON p.id = u.id
--  WHERE NULLIF(trim(p.country), '') IS NOT NULL
--    AND (u.raw_user_meta_data->>'country') IS DISTINCT FROM p.country
--  ORDER BY p.country_changed_at DESC NULLS LAST;

-- ---- 2. REPAIR --------------------------------------------------------
BEGIN;

UPDATE auth.users u
   SET raw_user_meta_data =
         COALESCE(u.raw_user_meta_data, '{}'::jsonb)
         || jsonb_build_object('country', p.country)
  FROM public.profiles p
 WHERE p.id = u.id
   AND NULLIF(trim(p.country), '') IS NOT NULL
   AND (u.raw_user_meta_data->>'country') IS DISTINCT FROM p.country;

-- Expect 0 after the update:
-- SELECT count(*) FROM auth.users u JOIN public.profiles p ON p.id = u.id
--  WHERE NULLIF(trim(p.country), '') IS NOT NULL
--    AND (u.raw_user_meta_data->>'country') IS DISTINCT FROM p.country;

COMMIT;
