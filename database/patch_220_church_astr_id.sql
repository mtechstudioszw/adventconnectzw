-- =====================================================================
--  PATCH 220 — astr_id on churches: the import must ADOPT, not duplicate
--
--  THE QUESTION THIS ANSWERS (founder, 19 Aug 2026): "what will you do
--  with the other 2,600 churches in Zim?"
--
--  They stay. They are not replaced, and they are not re-imported. Here is
--  why that matters, measured against the live database today:
--
--    2,600  churches
--      161  members whose profiles.church_id points at one of them
--      120  distinct churches with at least one member attached
--        9  approved church_admins rows
--        1  announcement
--
--  OrgMast covers Zimbabwe too. A naive "import everything" therefore
--  creates a SECOND row for Avondale SDA Church — and the damage is not
--  cosmetic:
--
--    * the congregation splits. Existing members stay on the old row;
--      everyone who joins after the import picks the new one out of the
--      church picker, because it is the one that looks canonical.
--    * announcements posted to one row are invisible to the other half.
--    * the 9 admins keep their rights over a row nobody new can find.
--    * changing church is gated to once per 14 days (patch_215), so a
--      member who picks the wrong duplicate is stuck with it for a
--      fortnight.
--
--  None of that is recoverable by deleting rows afterwards, because by
--  then real members are attached to both.
--
--  --------------------------------------------------------------------
--  SO: `astr_id` is the join key between our rows and OrgMast's.
--
--  The import becomes: for each incoming church, if its astr_id is already
--  here, UPDATE that row. Otherwise try to MATCH it to an existing row
--  (country + name + city) and, on a confident match, write the astr_id
--  onto the row we already have — adopting it rather than inserting a
--  twin. Only a church that matches nothing gets inserted.
--
--  UNIQUE makes the whole thing idempotent: re-running the import cannot
--  create a second copy of anything it has already seen, which matters
--  because a 185,000-row import WILL be interrupted at least once.
--
--  MATCHING IS NOT AUTOMATIC-SAFE HERE. There are already 34 groups of
--  rows sharing a name+city in the current 2,600 — the data is not clean
--  enough for a fuzzy match to be trusted blind. Ambiguous matches must go
--  to a human review queue, never straight into an UPDATE. Do not add a
--  "just take the closest one" shortcut to the importer.
--
--  NOTHING IS DELETED BY THIS PATCH. A church with members, admins,
--  announcements or events attached must never be removed by an import,
--  even if OrgMast has no record of it — a congregation that uses this app
--  is more authoritative about its own existence than a directory is.
-- =====================================================================

ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS astr_id TEXT;

-- Partial UNIQUE: many rows will have no astr_id for a long time (every
-- church a member suggested by hand), and a plain UNIQUE would treat those
-- NULLs as distinct anyway — this states the intent and stays cheap.
CREATE UNIQUE INDEX IF NOT EXISTS idx_churches_astr_id
  ON public.churches (astr_id)
  WHERE astr_id IS NOT NULL;

COMMENT ON COLUMN public.churches.astr_id IS
  'Adventist OrgMast (ASTR) identifier. The join key for the global import: '
  'present means this row is matched to the official directory. NULL means '
  'locally created (member suggestion) and not yet matched. Never insert a '
  'row whose astr_id already exists - adopt the existing row instead.';

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- SELECT count(*) AS total,
--        count(astr_id) AS matched_to_orgmast
--   FROM public.churches;
--   -- expect: 2600 total, 0 matched (nothing imported yet)
--
-- SELECT indexname FROM pg_indexes
--  WHERE schemaname='public' AND indexname='idx_churches_astr_id';
