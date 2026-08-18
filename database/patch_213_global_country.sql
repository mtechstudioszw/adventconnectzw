-- =====================================================================
--  PATCH 213 — Country, for the global rebrand
--
--  Adventist Super App serves Adventists worldwide, but every location
--  column in this schema is Zimbabwe-shaped: `province` means a ZIMBABWEAN
--  province, and there is no country anywhere. A member in Nairobi has no
--  way to say where they are, and a Nairobi job listing cannot satisfy
--  `jobs.province NOT NULL`.
--
--  This adds `country` ABOVE the existing province/city pair rather than
--  replacing anything. That is the whole trick: `province` keeps its
--  current meaning for ZW rows, every existing filter and index keeps
--  working untouched, and no data is migrated.
--
--  Country is stored as an ISO 3166-1 alpha-2 CODE ('ZW', 'KE', 'US') —
--  stable across display-name changes, cheap to index, and translatable.
--  The display name and flag are derived client-side in
--  lib/config/countries.dart. Never store the display name.
--
--  BACKFILL: every existing row becomes 'ZW'. That is correct rather than
--  merely convenient — the entire pre-rebrand user base, church directory
--  and marketplace is Zimbabwean. Founder's explicit call (18 Aug 2026):
--  tag everyone as Zimbabwe, let them change it in edit profile.
--
--  --------------------------------------------------------------------
--  CLAUDE.md `profiles` CHECKLIST — worked, not assumed:
--
--   1. Does profiles_block_privilege_self_grant() need to snap it back?
--      NO. Country is self-declared identity, not privilege. A member
--      setting their own country is the intended behaviour, and the
--      trigger's contract is "privileges cannot be self-granted". Adding
--      country there would BREAK edit-profile. Deliberately left out.
--
--   2. Does it need explicit grants? YES — and this is the trap that hid
--      the chat privacy screen for months (patch_192). `authenticated`
--      has NO table-level SELECT on profiles; patch_132 revoked it and
--      granted per-column. A new column therefore arrives UNREADABLE
--      unless granted here. Same for UPDATE, per patch_188.
--
--   3. Column-level REVOKE is ignored while a table grant exists — not
--      applicable here, we only GRANT.
--
--   4. BEFORE triggers covering DELETE must RETURN COALESCE(NEW, OLD) —
--      no new triggers in this patch.
--  --------------------------------------------------------------------
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. profiles.country
-- ---------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS country TEXT;

UPDATE public.profiles SET country = 'ZW' WHERE country IS NULL;

-- Deliberately NOT NOT-NULL. The signup trigger (patch_001) inserts the
-- profile row before onboarding runs, and a NOT NULL here would either
-- break that insert or force a DEFAULT 'ZW' — which would silently brand
-- every new Kenyan user Zimbabwean. The app requires it in onboarding
-- instead, where the user can actually see and change it.
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_country_iso2
  CHECK (country IS NULL OR country ~ '^[A-Z]{2}$');

CREATE INDEX IF NOT EXISTS idx_profiles_country ON public.profiles (country);

-- THE GRANTS. Without these the column is invisible and unwritable to
-- every client, with no error — the failure mode is a screen that simply
-- never loads. SELECT matches patch_132 (authenticated only; anon holds
-- no read on profiles by design). UPDATE matches patch_188's
-- non-protected column set, so a future re-run of that rebuild agrees
-- with what we do here.
GRANT SELECT (country) ON public.profiles TO authenticated;
GRANT UPDATE (country) ON public.profiles TO authenticated, anon;

-- ---------------------------------------------------------------------
--  2. Content tables — country for scoping
--
--  The feed is country-first with a worldwide toggle; marketplace and
--  jobs are country-scoped by default (founder, 18 Aug 2026), because
--  handoff is WhatsApp plus local pickup and a cross-border listing is
--  one nobody can act on.
-- ---------------------------------------------------------------------
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE public.events   ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE public.jobs     ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE public.sellers  ADD COLUMN IF NOT EXISTS country TEXT;

UPDATE public.churches SET country = 'ZW' WHERE country IS NULL;
UPDATE public.events   SET country = 'ZW' WHERE country IS NULL;
UPDATE public.jobs     SET country = 'ZW' WHERE country IS NULL;
UPDATE public.products SET country = 'ZW' WHERE country IS NULL;
UPDATE public.sellers  SET country = 'ZW' WHERE country IS NULL;

ALTER TABLE public.churches ALTER COLUMN country SET DEFAULT 'ZW';
ALTER TABLE public.events   ALTER COLUMN country SET DEFAULT 'ZW';
ALTER TABLE public.jobs     ALTER COLUMN country SET DEFAULT 'ZW';
ALTER TABLE public.products ALTER COLUMN country SET DEFAULT 'ZW';
ALTER TABLE public.sellers  ALTER COLUMN country SET DEFAULT 'ZW';

CREATE INDEX IF NOT EXISTS idx_churches_country ON public.churches (country);
CREATE INDEX IF NOT EXISTS idx_events_country   ON public.events   (country);
CREATE INDEX IF NOT EXISTS idx_jobs_country     ON public.jobs     (country);
CREATE INDEX IF NOT EXISTS idx_products_country ON public.products (country);
CREATE INDEX IF NOT EXISTS idx_sellers_country  ON public.sellers  (country);

-- The church directory's real browse path becomes country → city, and at
-- global scale (≈107,000 SDA churches worldwide against the ~2,600 ZW
-- rows here today) an unindexed country+name scan is not viable.
CREATE INDEX IF NOT EXISTS idx_churches_country_city
  ON public.churches (country, city);

-- ---------------------------------------------------------------------
--  3. jobs.province stops being mandatory
--
--  `province` is a Zimbabwean administrative unit. Requiring it made
--  every non-ZW job listing impossible to insert. Country now carries the
--  coarse location and province degrades to an optional region/state.
-- ---------------------------------------------------------------------
ALTER TABLE public.jobs ALTER COLUMN province DROP NOT NULL;

-- ---------------------------------------------------------------------
--  4. Verification
--
--  Per the standing rule that "it ran" is not proof: run these and read
--  the output. The grants query is the one that matters — a missing row
--  there is the silent failure this patch exists to avoid.
-- ---------------------------------------------------------------------
-- SELECT column_name, is_nullable, column_default
--   FROM information_schema.columns
--  WHERE table_schema='public' AND column_name='country'
--  ORDER BY table_name;
--
-- SELECT grantee, privilege_type
--   FROM information_schema.column_privileges
--  WHERE table_schema='public' AND table_name='profiles'
--    AND column_name='country';
--   -- expect: authenticated SELECT, authenticated UPDATE, anon UPDATE
--
-- SELECT country, count(*) FROM public.profiles GROUP BY 1;
--   -- expect: every existing row 'ZW', none NULL
