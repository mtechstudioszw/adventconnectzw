-- patch_207 — the number on a church card should be MEMBERS, not followers.
--
-- WHY
-- The founder asked (17 Aug) to "verify the member count shown per church is
-- actually the number of Advent Connect members in that church". Measured
-- against production, it is not:
--
--   profiles.church_id       "this is my church"    156 across 116 churches
--   churches.follower_count  "I follow this church" 158 across 117 churches
--
-- Similar magnitude, different sets — you can follow a church you do not
-- attend, and a member may never tap Follow. The card reads follower_count
-- and labels it "N on Advent", which hides the mismatch rather than making
-- it true.
--
-- (churches.members_count is a separate dead column: 0 for all 2,600 rows.
-- It is NOT the bug — church_model.dart already prefers follower_count — and
-- it is deliberately left alone here rather than dropped, so this patch is
-- purely additive.)
--
-- ## An RPC, not a trigger
--
-- The tempting design is a `member_count` column kept up to date by a
-- trigger on `profiles`. This does not do that, on purpose. CLAUDE.md's
-- loudest warning is about triggers touching `profiles` — three separate
-- production bugs in one day came from it, including a BEFORE...DELETE
-- trigger returning NULL that silently cancelled every delete in the app
-- across 26 tables. A read-only aggregate cannot do that.
--
-- `profiles.church_id` is already indexed, and the counts are tiny.

create or replace function public.church_member_counts(p_ids bigint[])
returns table (church_id bigint, members integer)
language sql
stable
security definer
set search_path = public
as $$
  select p.church_id, count(*)::integer as members
    from public.profiles p
   where p.church_id = any(p_ids)
   group by p.church_id;
$$;

comment on function public.church_member_counts(bigint[]) is
  'Advent Connect members whose home church is each of p_ids. This is '
  'membership (profiles.church_id), NOT followers (churches.follower_count) '
  '- the two are different sets. Returns bare counts only: no identities, '
  'matching the privacy posture of church_friend_counts (patch_176).';

-- SECURITY DEFINER so the count works regardless of who is asking, while
-- still leaking nothing but a number. It deliberately returns NO rows for a
-- church with no members, so the client treats "absent" as zero rather than
-- the function inventing rows for 2,600 churches.
--
-- REVOKE FROM public is NOT enough on Supabase: EXECUTE is granted to anon
-- and authenticated explicitly, so both must be revoked by name before
-- granting back only what is wanted. Verify with has_function_privilege.
revoke all on function public.church_member_counts(bigint[]) from public;
revoke all on function public.church_member_counts(bigint[]) from anon;
revoke all on function public.church_member_counts(bigint[]) from authenticated;
grant execute on function public.church_member_counts(bigint[]) to authenticated;

-- Sanity:
--   select has_function_privilege('anon',
--     'public.church_member_counts(bigint[])', 'execute');          -- false
--   select has_function_privilege('authenticated',
--     'public.church_member_counts(bigint[])', 'execute');          -- true
