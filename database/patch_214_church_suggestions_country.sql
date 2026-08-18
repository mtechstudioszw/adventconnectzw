-- =====================================================================
--  PATCH 214 — country on church_suggestions
--
--  patch_213 put `country` on churches, events, jobs, products, sellers
--  and profiles — but not on `church_suggestions`, the inbox the "Add a
--  missing church" form writes to. So the one screen where a member in
--  Nairobi tells us about a church we have never heard of was still the
--  one screen with nowhere to record that it is in Kenya, and the
--  suggestion arrived indistinguishable from a Zimbabwean one.
--
--  Same shape as 213: ISO 3166-1 alpha-2 code, backfilled 'ZW', DEFAULT
--  'ZW'. `province` here was already nullable, so nothing to relax.
--
--  IDEMPOTENT: yes. Every statement is IF NOT EXISTS or a no-op on a
--  second run, and it does NOT depend on 213 having been applied — run
--  it before or after, in either order.
--
--  --------------------------------------------------------------------
--  CLAUDE.md `profiles` CHECKLIST — not applicable, and why:
--
--   1. profiles_block_privilege_self_grant() — untouched. This patch
--      does not go near `profiles`.
--   2. Explicit column grants — NOT needed. The per-column grant trap is
--      specific to `profiles`, where patch_132 revoked the table-level
--      SELECT. `church_suggestions` holds its normal table-level grants
--      + RLS from patch_002, so a new column is readable and writable by
--      whoever the existing policies already allow. This mirrors what
--      213 did for churches/events/jobs/products/sellers.
--   3. Column-level REVOKE — not applicable, nothing is revoked.
--   4. BEFORE ... DELETE triggers — none added.
--  --------------------------------------------------------------------
-- =====================================================================

ALTER TABLE public.church_suggestions
  ADD COLUMN IF NOT EXISTS country TEXT;

UPDATE public.church_suggestions SET country = 'ZW' WHERE country IS NULL;

-- DEFAULT 'ZW' matches 213's other content tables. It is a safety net for
-- an older client that does not send the column, NOT the mechanism — the
-- app now always sends an explicit country from the form.
ALTER TABLE public.church_suggestions ALTER COLUMN country SET DEFAULT 'ZW';

CREATE INDEX IF NOT EXISTS idx_church_suggestions_country
  ON public.church_suggestions (country);

-- ---------------------------------------------------------------------
--  Verification — run these and read the output; "it ran" is not proof.
-- ---------------------------------------------------------------------
-- SELECT column_name, is_nullable, column_default
--   FROM information_schema.columns
--  WHERE table_schema='public' AND table_name='church_suggestions'
--    AND column_name IN ('country','province');
--   -- expect: country YES 'ZW'::text, province YES (no default)
--
-- SELECT country, count(*) FROM public.church_suggestions GROUP BY 1;
--   -- expect: every existing row 'ZW', none NULL
