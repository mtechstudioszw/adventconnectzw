-- =====================================================================
--  PATCH 201 — the profiles SELECT policy respects blocks BOTH ways
--
--  THE BUG
--
--  patch_200 made `is_blocked_by()` symmetric and fixed posts, stories
--  and prayers. It deliberately touched no policy ("RLS: no policy
--  created, altered or dropped") — which is why this one survived.
--
--  `profiles_select_discoverable_or_self` never called the helper. It
--  carried its OWN inline copy of the old one-directional test:
--
--      NOT EXISTS (SELECT 1 FROM blocked_users b
--                   WHERE b.blocker_id = profiles.id
--                     AND b.blocked_id = auth.uid())
--      -- "has THEY blocked ME?"
--
--  So the person doing the blocking got no relief anywhere that reads
--  `profiles` directly:
--
--    * They block you -> their profile disappears for you.  OK.
--    * YOU block them -> blocker_id is you, not them, so this is false
--                        and THEY STAY IN YOUR SUGGESTIONS AND BROWSE
--                        LISTS.
--
--  Measured on production before this patch, as the blocker:
--
--    direct profiles read (suggestions / "find people")  -> VISIBLE
--    search_profiles() RPC                               -> hidden
--
--  Search was already right because patch_179 routed it through
--  `is_blocked_by()`. Only the raw-table readers leaked, which is
--  exactly the reported symptom: "blocked users still appear in search
--  and people you may know".
--
--  This is one policy rather than three Dart patches on purpose. The
--  leaking callers are DirectoryService.fetchSuggestedMembers,
--  .fetchAllDiscoverableProfiles and .fetchEntries' profiles join, and
--  any future direct read would leak the same way. Fixing the row
--  visibility fixes all of them at once and cannot be forgotten by the
--  next caller.
--
--  SAFETY
--
--  * Same helper patch_200 already uses, so blocking has ONE definition
--    across feed, stories, prayers, search and now profiles.
--  * `auth.uid() = id` stays the first branch, so you can always see
--    yourself; `blocked_users_not_self` forbids self-blocks anyway.
--  * `is_blocked_by()` is STABLE SECURITY DEFINER and already granted to
--    `authenticated` (patch_200), which is what lets the policy read
--    blocked_users rows the viewer cannot see under that table's own RLS.
--    An inline EXISTS here would be subject to blocked_users' RLS and is
--    the reason the helper exists.
--  * `auth.uid()` is NULL for anon; the policy already requires
--    `auth.role() = 'authenticated'`, so anon is unaffected.
--
--  RLS: replaces exactly one SELECT policy on public.profiles.
--  IDEMPOTENT: yes — DROP ... IF EXISTS then CREATE.
-- =====================================================================


-- ----- 1. Symmetric visibility -------------------------------------
DROP POLICY IF EXISTS profiles_select_discoverable_or_self ON public.profiles;

CREATE POLICY profiles_select_discoverable_or_self
  ON public.profiles
  FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND (
      auth.uid() = id
      OR (
        is_discoverable = TRUE
        AND is_banned = FALSE
        -- Both directions. This is the only line that changed.
        AND NOT public.is_blocked_by(profiles.id)
      )
    )
  );


-- ----- 2. Index the reverse direction -------------------------------
-- is_blocked_by() now probes blocked_users by EITHER column. The
-- blocker_id side is covered by the table's existing key; without this
-- the blocked_id side is a sequential scan on every row the policy
-- tests, which is once per candidate profile in a suggestions query.
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_id
  ON public.blocked_users (blocked_id, blocker_id);
