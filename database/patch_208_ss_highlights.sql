-- =====================================================================
--  PATCH 208 — Sabbath School highlights, following the ACCOUNT
--
--  Founder, 18 Aug 2026: highlighting does not work in Sabbath School at
--  all — it is EGW-only. Asked on 19 Aug whether an SS highlight should
--  follow the account or stay on the device, he chose **the account**.
--
--  ## Why this is a table and EGW's highlights are not
--
--  EGW highlights live in Hive under an unprefixed key, so `clearUserData()`
--  wipes them on sign-out. That is right for a device-local store on a
--  shared phone. It is also why they do not survive a reinstall, and why
--  they are invisible on a second device.
--
--  Following the account means the opposite trade, deliberately: the rows
--  outlive the handset, and the ONLY thing keeping one member's study notes
--  away from another is RLS. So the policies below are the feature, not
--  paperwork around it.
--
--  ## Matched by TEXT, not by offsets
--
--  Same decision as `EgwHighlights`, for the same reason. The reader
--  reflows: type size, viewport and orientation all change where a
--  character sits, and the Adventech HTML can be re-parsed at any time. An
--  offset into "the page" is meaningless by the next session; the passage
--  itself is stable against all of it.
--
--  The known cost is duplicates — a sentence appearing twice in one day's
--  reading highlights both. Rare, and far better than a highlight that
--  silently drifts onto the wrong sentence.
--
--  ## Keyed by read_path
--
--  `read_path` is what the app already uses to fetch and cache a day
--  (`ss:read:<path>`), and it carries language, quarterly, lesson and day
--  in one string. Storing the parts separately would invite them to drift
--  out of step with the path the reader actually opened.
--
--  Note this makes highlights language-specific by construction: the Shona
--  and English editions of one day are different `read_path`s, and the
--  sentences are different sentences. That is correct, not a limitation.
--
--  IDEMPOTENT: yes. Safe to re-run.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.ss_highlights (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- e.g. 'en/quarterlies/2026-03/lessons/05/days/02/read'
  read_path  TEXT NOT NULL CHECK (length(btrim(read_path)) BETWEEN 3 AND 400),
  -- The highlighted sentence, whitespace already collapsed by the client so
  -- a passage stored from a wrapped line still matches the source text.
  passage    TEXT NOT NULL CHECK (length(btrim(passage)) BETWEEN 3 AND 2000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Highlighting the same sentence twice is a toggle, not a second row.
  -- This also makes the client's "add" an idempotent upsert.
  UNIQUE (user_id, read_path, passage)
);

-- The only query the app makes: everything I highlighted in this day.
CREATE INDEX IF NOT EXISTS idx_ss_highlights_user_day
  ON public.ss_highlights (user_id, read_path);

COMMENT ON TABLE public.ss_highlights IS
  'Sabbath School highlights, per ACCOUNT (founder decision, 19 Aug 2026). '
  'Matched by passage TEXT rather than character offsets because the reader '
  'reflows and the source HTML can be re-parsed — see patch header.';

ALTER TABLE public.ss_highlights ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
--  Policies — one per verb, each independently owner-only.
--
--  Written out rather than a single FOR ALL policy on purpose. A FOR ALL
--  policy applies its USING clause to SELECT/UPDATE/DELETE and its WITH
--  CHECK to INSERT/UPDATE, and it is easy to leave one half implicit and
--  wrong. `.upsert()` in particular needs SELECT *and* INSERT *and* UPDATE
--  to be right, and a missing SELECT policy is exactly the trap that has
--  already bitten this project once.
-- ---------------------------------------------------------------------

DROP POLICY IF EXISTS ss_highlights_select_own ON public.ss_highlights;
CREATE POLICY ss_highlights_select_own ON public.ss_highlights
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS ss_highlights_insert_own ON public.ss_highlights;
CREATE POLICY ss_highlights_insert_own ON public.ss_highlights
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS ss_highlights_update_own ON public.ss_highlights;
CREATE POLICY ss_highlights_update_own ON public.ss_highlights
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS ss_highlights_delete_own ON public.ss_highlights;
CREATE POLICY ss_highlights_delete_own ON public.ss_highlights
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Supabase grants table privileges to anon AND authenticated by default on
-- new tables. RLS would refuse anon anyway (auth.uid() is NULL), but an
-- anonymous caller has no business holding the grant at all — and a
-- table-level grant left in place is what makes a later column-level
-- REVOKE silently do nothing.
REVOKE ALL ON TABLE public.ss_highlights FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ss_highlights
  TO authenticated;

-- =====================================================================
--  VERIFY (run separately; do not paste into the patch)
--
--    SELECT policyname, cmd FROM pg_policies
--     WHERE tablename = 'ss_highlights' ORDER BY policyname;
--    -- expect exactly four: delete/insert/select/update, all _own
--
--    SELECT has_table_privilege('anon', 'public.ss_highlights', 'SELECT');
--    -- expect FALSE
--
--    SELECT has_table_privilege('authenticated','public.ss_highlights','SELECT');
--    -- expect TRUE
-- =====================================================================
