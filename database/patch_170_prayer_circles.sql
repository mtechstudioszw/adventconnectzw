-- =====================================================================
--  PATCH 170 — Prayer circles
--
--  Some things you want fifty people praying about. Some you want five.
--  Today every request goes to the whole app, so the second kind simply
--  doesn't get posted. A circle is a named, invite-only group; a prayer
--  may carry a `circle_id`, and only members can read it.
--
--  ── Why the policies below are written out in full ──────────────────
--  The live policies were READ from pg_policies before writing this, and
--  they are richer than the repo suggested. `prayers_select_visible`
--  already encodes public/anonymous, own-row, AND church_only access via
--  church_followers or a matching profiles.church_id.
--  `prayers_insert_self` additionally requires user_is_active().
--
--  So this patch REPLACES those two policies with the same logic plus a
--  circle gate. It does not invent simpler ones: dropping and rewriting
--  `prayers_select_visible` naively would have made every church_only
--  prayer world-readable, and rewriting the INSERT policy naively would
--  have let banned accounts post again.
--
--  `prayers_hide_from_blocked` is RESTRICTIVE and is deliberately left
--  untouched — it ANDs with whatever permissive policy allows the row,
--  so block semantics keep working without being restated here.
--
--  SECURITY IS THE WHOLE FEATURE. A circle prayer that leaks is worse
--  than no circles at all; people put the hardest things in the small
--  group. Membership is checked through a SECURITY DEFINER helper
--  because a policy on prayer_circle_members that itself queries
--  prayer_circle_members recurses infinitely.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.prayer_circles (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 60),
  owner_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prayer_circle_members (
  circle_id UUID NOT NULL REFERENCES public.prayer_circles(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  added_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (circle_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_prayer_circle_members_user
  ON public.prayer_circle_members (user_id);

-- Nullable: NULL means existing behaviour, so every prayer already in
-- the table keeps working untouched.
ALTER TABLE public.prayers
  ADD COLUMN IF NOT EXISTS circle_id UUID
    REFERENCES public.prayer_circles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_prayers_circle
  ON public.prayers (circle_id)
  WHERE circle_id IS NOT NULL;

COMMENT ON COLUMN public.prayers.circle_id IS
  'NULL = normal visibility rules. Non-null = readable only by members '
  'of that circle (enforced in RLS, not the client).';

-- ── Membership helper ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_circle_member(p_circle UUID, p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.prayer_circle_members m
     WHERE m.circle_id = p_circle AND m.user_id = p_user
  );
$$;

REVOKE ALL ON FUNCTION public.is_circle_member(UUID, UUID) FROM public;
GRANT EXECUTE ON FUNCTION public.is_circle_member(UUID, UUID) TO authenticated;

-- ── RLS: circles + membership ────────────────────────────────────────
ALTER TABLE public.prayer_circles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayer_circle_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prayer_circles_select ON public.prayer_circles;
CREATE POLICY prayer_circles_select ON public.prayer_circles
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_circle_member(id, auth.uid()));

DROP POLICY IF EXISTS prayer_circles_insert ON public.prayer_circles;
CREATE POLICY prayer_circles_insert ON public.prayer_circles
  FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS prayer_circles_update ON public.prayer_circles;
CREATE POLICY prayer_circles_update ON public.prayer_circles
  FOR UPDATE TO authenticated USING (owner_id = auth.uid());

DROP POLICY IF EXISTS prayer_circles_delete ON public.prayer_circles;
CREATE POLICY prayer_circles_delete ON public.prayer_circles
  FOR DELETE TO authenticated USING (owner_id = auth.uid());

DROP POLICY IF EXISTS prayer_circle_members_select ON public.prayer_circle_members;
CREATE POLICY prayer_circle_members_select ON public.prayer_circle_members
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.prayer_circles c
       WHERE c.id = prayer_circle_members.circle_id
         AND c.owner_id = auth.uid()
    )
    OR public.is_circle_member(circle_id, auth.uid())
  );

-- Only the owner adds people. Circles are small and personal; open
-- self-join would let anyone walk into a family's prayer group.
DROP POLICY IF EXISTS prayer_circle_members_insert ON public.prayer_circle_members;
CREATE POLICY prayer_circle_members_insert ON public.prayer_circle_members
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.prayer_circles c
       WHERE c.id = prayer_circle_members.circle_id
         AND c.owner_id = auth.uid()
    )
  );

-- Owner can remove anyone; a member can always remove themselves.
DROP POLICY IF EXISTS prayer_circle_members_delete ON public.prayer_circle_members;
CREATE POLICY prayer_circle_members_delete ON public.prayer_circle_members
  FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.prayer_circles c
       WHERE c.id = prayer_circle_members.circle_id
         AND c.owner_id = auth.uid()
    )
  );

-- ── RLS: prayers — original logic PLUS a circle gate ─────────────────
-- The inner block is the live `prayers_select_visible` predicate,
-- reproduced exactly. The only addition is the leading circle gate.
DROP POLICY IF EXISTS prayers_select_visible ON public.prayers;
CREATE POLICY prayers_select_visible ON public.prayers
  FOR SELECT
  USING (
    (
      circle_id IS NULL
      OR author_id = auth.uid()
      OR public.is_circle_member(circle_id, auth.uid())
    )
    AND (
      (auth.role() = 'authenticated'::text)
      AND (
        (visibility = ANY (ARRAY['public'::text, 'anonymous'::text]))
        OR (author_id = auth.uid())
        OR (
          visibility = 'church_only'::text
          AND church_id IS NOT NULL
          AND (
            EXISTS (
              SELECT 1 FROM public.church_followers cf
               WHERE cf.church_id = prayers.church_id
                 AND cf.user_id = auth.uid()
            )
            OR EXISTS (
              SELECT 1 FROM public.profiles p
               WHERE p.id = auth.uid()
                 AND p.church_id = prayers.church_id
            )
          )
        )
      )
    )
  );

-- Same as the live `prayers_insert_self` (including user_is_active(), so
-- banned accounts stay unable to post) plus: you may only post INTO a
-- circle you belong to, so the picker can't be bypassed by a crafted
-- insert.
DROP POLICY IF EXISTS prayers_insert_self ON public.prayers;
CREATE POLICY prayers_insert_self ON public.prayers
  FOR INSERT
  WITH CHECK (
    auth.uid() = author_id
    AND user_is_active()
    AND (
      circle_id IS NULL
      OR public.is_circle_member(circle_id, auth.uid())
    )
  );
