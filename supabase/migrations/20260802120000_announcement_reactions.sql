-- Announcement reactions: members react to a church announcement, the
-- admin sees the breakdown in their dashboard, and admins are notified.
--
-- Built on the same shapes patch_173 established for announcement_reads +
-- church_announcement_reach(), and patch_181's nudge_profile_incomplete()
-- for the notification writer. `notifications` has NO client INSERT policy
-- by design, so anything that writes one is SECURITY DEFINER.

-- ---------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------
-- One reaction per member per announcement: reacting again REPLACES your
-- reaction rather than adding a second, which is why the PK is the pair.
create table if not exists public.announcement_reactions (
  announcement_id bigint      not null
    references public.announcements(id) on delete cascade,
  user_id         uuid        not null
    references auth.users(id) on delete cascade,
  reaction        text        not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (announcement_id, user_id),
  -- Constrained on purpose. An open text column becomes an emoji dumping
  -- ground and makes the admin breakdown unaggregatable.
  constraint announcement_reactions_kind_check
    check (reaction in ('amen', 'praise', 'pray', 'love'))
);

-- The two reads this table gets: counts for one announcement, and the
-- admin rollup across a church's announcements.
create index if not exists announcement_reactions_announcement_idx
  on public.announcement_reactions (announcement_id);

alter table public.announcement_reactions enable row level security;

-- Counts are public to signed-in members, matching announcements_select_all
-- (`auth.role() = 'authenticated'`) — you can already read every
-- announcement, so you can see how people responded to it.
drop policy if exists announcement_reactions_select_all
  on public.announcement_reactions;
create policy announcement_reactions_select_all
  on public.announcement_reactions
  for select
  using (auth.role() = 'authenticated');

-- SELECT + INSERT + UPDATE + DELETE on your own row. All four exist
-- deliberately: a supabase-dart .upsert() is
-- `INSERT … ON CONFLICT DO UPDATE … RETURNING`, so a table missing SELECT
-- or UPDATE raises 42501 and the failure is usually swallowed by a catch.
-- That has bitten this project three times (signup_surveys, story_likes,
-- youtube_subscriptions). The client goes through
-- set_announcement_reaction() below rather than upserting, but the
-- policies are complete so a direct write can't fail silently either.
drop policy if exists announcement_reactions_insert_own
  on public.announcement_reactions;
create policy announcement_reactions_insert_own
  on public.announcement_reactions
  for insert
  with check (user_id = auth.uid());

drop policy if exists announcement_reactions_update_own
  on public.announcement_reactions;
create policy announcement_reactions_update_own
  on public.announcement_reactions
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists announcement_reactions_delete_own
  on public.announcement_reactions;
create policy announcement_reactions_delete_own
  on public.announcement_reactions
  for delete
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 2. Notify the church's admins
-- ---------------------------------------------------------------------
-- COLLAPSING, not one-per-reaction. A popular notice would otherwise fire
-- a notification per member per admin. Instead each admin gets ONE live
-- notification per announcement, whose body is rewritten with the running
-- count while it is still unread. Once they have read it, the next
-- reaction starts a fresh one.
create or replace function public.notify_admins_of_announcement_reaction()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_church_id bigint;
  v_title     text;
  v_total     integer;
  v_admin     uuid;
begin
  select a.church_id, a.title into v_church_id, v_title
    from public.announcements a
   where a.id = new.announcement_id;

  if v_church_id is null then
    return new;
  end if;

  select count(*)::int into v_total
    from public.announcement_reactions r
   where r.announcement_id = new.announcement_id;

  for v_admin in
    select ca.user_id
      from public.church_admins ca
     where ca.church_id = v_church_id
       and ca.status = 'approved'
       -- Don't tell an admin about their own reaction.
       and ca.user_id <> new.user_id
  loop
    update public.notifications n
       set body = case
                    when v_total = 1
                      then 'Someone reacted to "' || v_title || '".'
                    else v_total || ' members have reacted to "'
                         || v_title || '".'
                  end,
           created_at = now()
     where n.user_id = v_admin
       and n.type = 'announcement_reaction'
       and n.reference_id = new.announcement_id::text
       and n.is_read = false;

    if not found then
      insert into public.notifications
        (user_id, title, body, type, reference_id, reference_type)
      values (
        v_admin,
        'New reaction',
        case
          when v_total = 1 then 'Someone reacted to "' || v_title || '".'
          else v_total || ' members have reacted to "' || v_title || '".'
        end,
        'announcement_reaction',
        new.announcement_id::text,
        'announcement'
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists announcement_reactions_notify
  on public.announcement_reactions;
create trigger announcement_reactions_notify
  after insert or update on public.announcement_reactions
  for each row
  execute function public.notify_admins_of_announcement_reaction();

-- ---------------------------------------------------------------------
-- 3. Set / clear my reaction
-- ---------------------------------------------------------------------
-- A dedicated RPC rather than a client-side .upsert(), for two reasons:
-- it sidesteps the upsert-RETURNING/RLS trap entirely, and it hands back
-- the fresh counts in the SAME round trip so the UI doesn't have to
-- re-query to show the number it just changed.
--
-- Passing NULL (or the reaction you already have) CLEARS it, so the same
-- call handles react / change / un-react — which is what tapping the same
-- face twice should do.
create or replace function public.set_announcement_reaction(
  p_announcement_id bigint,
  p_reaction        text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me      uuid := auth.uid();
  v_current text;
  v_mine    text;
begin
  if v_me is null then
    raise exception 'Not signed in';
  end if;

  if p_reaction is not null
     and p_reaction not in ('amen', 'praise', 'pray', 'love') then
    raise exception 'Unknown reaction: %', p_reaction;
  end if;

  select r.reaction into v_current
    from public.announcement_reactions r
   where r.announcement_id = p_announcement_id
     and r.user_id = v_me;

  if p_reaction is null or p_reaction = v_current then
    delete from public.announcement_reactions
     where announcement_id = p_announcement_id
       and user_id = v_me;
  else
    insert into public.announcement_reactions
      (announcement_id, user_id, reaction)
    values (p_announcement_id, v_me, p_reaction)
    on conflict (announcement_id, user_id)
    do update set reaction = excluded.reaction, updated_at = now();
  end if;

  select r.reaction into v_mine
    from public.announcement_reactions r
   where r.announcement_id = p_announcement_id
     and r.user_id = v_me;

  return jsonb_build_object(
    'mine', v_mine,
    'counts', coalesce((
      select jsonb_object_agg(k.reaction, k.n)
        from (
          select r.reaction, count(*)::int as n
            from public.announcement_reactions r
           where r.announcement_id = p_announcement_id
           group by r.reaction
        ) k
    ), '{}'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Read reactions for a batch of announcements
-- ---------------------------------------------------------------------
-- The list screen renders many announcements at once; one call per row
-- would be N round trips.
create or replace function public.announcement_reactions_for(
  p_ids bigint[]
)
returns table (
  announcement_id bigint,
  counts          jsonb,
  mine            text
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select a.id,
         coalesce((
           select jsonb_object_agg(k.reaction, k.n)
             from (
               select r.reaction, count(*)::int as n
                 from public.announcement_reactions r
                where r.announcement_id = a.id
                group by r.reaction
             ) k
         ), '{}'::jsonb),
         (select r2.reaction
            from public.announcement_reactions r2
           where r2.announcement_id = a.id
             and r2.user_id = auth.uid())
    from public.announcements a
   where a.id = any(p_ids)
     and auth.role() = 'authenticated';
$$;

-- ---------------------------------------------------------------------
-- 5. Admin analytics
-- ---------------------------------------------------------------------
-- Mirrors church_announcement_reach(): same admin gate, same shape, so
-- the dashboard can put reach and reactions side by side.
create or replace function public.church_announcement_reactions(
  p_church_id bigint,
  p_limit     integer default 8
)
returns table (
  id             bigint,
  title          text,
  category       text,
  created_at     timestamptz,
  read_count     integer,
  reaction_count integer,
  counts         jsonb
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select a.id, a.title, a.category, a.created_at,
         (select count(*)::int from public.announcement_reads rd
           where rd.announcement_id = a.id),
         (select count(*)::int from public.announcement_reactions r
           where r.announcement_id = a.id),
         coalesce((
           select jsonb_object_agg(k.reaction, k.n)
             from (
               select r.reaction, count(*)::int as n
                 from public.announcement_reactions r
                where r.announcement_id = a.id
                group by r.reaction
             ) k
         ), '{}'::jsonb)
    from public.announcements a
   where a.church_id = p_church_id
     and (
       public.is_super_admin()
       or exists (
         select 1 from public.church_admins ca
          where ca.church_id = p_church_id
            and ca.user_id = auth.uid()
            and ca.status = 'approved'
       )
     )
   order by a.created_at desc
   limit greatest(1, least(coalesce(p_limit, 8), 30));
$$;

grant execute on function public.set_announcement_reaction(bigint, text)
  to authenticated;
grant execute on function public.announcement_reactions_for(bigint[])
  to authenticated;
grant execute on function public.church_announcement_reactions(bigint, integer)
  to authenticated;
