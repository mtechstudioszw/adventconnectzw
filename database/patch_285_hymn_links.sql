-- ============================================================================
--  patch_285 — Christ in Song number → SDA Hymnal number
--  STATUS: APPLIED 29 Oct 2026 (by the owner, verified)
-- ============================================================================
--
--  Owner, 29 Oct 2026: "number one in Kristu MuNzwiyo … an option to switch
--  it to the actual number in the Seventh-day Adventist Hymnal".
--
--  The 300 Christ in Song hymns share ONE numbering across every vernacular
--  edition (Shona Kristu MuNzwiyo, Ndebele, Zulu, Xhosa, Tswana, Sotho,
--  Chichewa, Venda, Tonga, Tsonga …), so a single row per number links every
--  language at once. Many of the 300 are also in the 1985 SDA Hymnal under a
--  different number; some are not (they come from the 1908 Christ in Song and
--  were never carried over), and those simply have no row.
--
--  Filled in by super admins from the printed hymnal (Admin → Library →
--  Hymns → edit a Kristu MuNzwiyo hymn → "Same hymn in the SDA Hymnal").
--  Nothing is guessed: no row means no link is shown.
--
--  No triggers, so the BEFORE-trigger COALESCE rule does not arise; not a
--  profiles change.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.hymn_links (
  cis_number  integer PRIMARY KEY CHECK (cis_number BETWEEN 1 AND 1000),
  sda_number  integer NOT NULL CHECK (sda_number BETWEEN 1 AND 695),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid DEFAULT auth.uid()
);

ALTER TABLE public.hymn_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hymn_links_read ON public.hymn_links;
CREATE POLICY hymn_links_read ON public.hymn_links
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS hymn_links_admin_write ON public.hymn_links;
CREATE POLICY hymn_links_admin_write ON public.hymn_links
  FOR ALL TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

REVOKE ALL ON public.hymn_links FROM anon, authenticated;
GRANT SELECT ON public.hymn_links TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.hymn_links TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
