-- =====================================================================
--  PATCH 176 — Service times, and "N friends here"
--
--  Both are things the redesigned Churches tab shows on every row, and
--  neither existed. `churches` has 26 columns and not one of them says
--  when the church actually meets — the single most useful fact about a
--  church to someone deciding whether to visit it.
--
--  WHAT:
--    1. churches.service_times JSONB — an array of
--         {"label": "Sabbath School", "day": "Saturday", "time": "08:30"}
--       Free-form on purpose: Zimbabwean congregations vary (some run two
--       Divine Services, some add Wednesday prayer meeting), and a fixed
--       pair of columns would have to be migrated the first time one
--       didn't fit. Written by church admins through the edit screen.
--    2. church_friend_counts(church_ids) — how many of the caller's
--       ACCEPTED friends belong to each church. One round trip for a
--       whole screenful instead of a query per row.
--
--  PRIVACY: the friend count is computed from the CALLER's own
--  friendships and returns a number, never a name or an id. It cannot
--  tell you anything about a church you couldn't learn by opening your
--  own friends list. Members who set no church_id are simply not counted.
--
--  RLS: adds a column to an existing table and creates one function. No
--  policy is created, altered or dropped — the existing churches
--  policies keep governing reads and writes of the new column.
--  IDEMPOTENT: yes.
-- =====================================================================

ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS service_times JSONB;

COMMENT ON COLUMN public.churches.service_times IS
  'Array of {label, day, time}. Edited by approved church admins.';


-- ---------------------------------------------------------------------
--  "3 friends here"
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.church_friend_counts(p_church_ids BIGINT[])
RETURNS TABLE (church_id BIGINT, friend_count INTEGER)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT p.church_id, count(*)::int
    FROM public.profiles p
   WHERE p.church_id = ANY(p_church_ids)
     AND auth.uid() IS NOT NULL
     AND p.id <> auth.uid()
     AND EXISTS (
       SELECT 1 FROM public.friendships f
        WHERE f.status = 'accepted'
          AND ((f.requester_id = auth.uid() AND f.addressee_id = p.id)
            OR (f.addressee_id = auth.uid() AND f.requester_id = p.id))
     )
   GROUP BY p.church_id;
$$;

REVOKE ALL ON FUNCTION public.church_friend_counts(BIGINT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_friend_counts(BIGINT[]) TO authenticated;


-- =====================================================================
--  VERIFY
--    SELECT id, name, service_times FROM churches
--     WHERE service_times IS NOT NULL LIMIT 5;
--    SELECT * FROM church_friend_counts(ARRAY[1,2,3]::bigint[]);
-- =====================================================================
