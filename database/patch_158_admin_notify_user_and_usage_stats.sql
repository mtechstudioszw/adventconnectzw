-- patch_158: admin-web — notify an individual user + app-usage stats.
-- Applied to production via the Supabase Management API on 2026-07-07.
--
-- 1) admin_notify_user(uuid, title, body): super-admin sends an in-app
--    notification (type 'admin_direct') to ONE user. The existing
--    " notify-fcm-on-notification-insert" trigger on public.notifications
--    delivers the push automatically — same pipeline as admin_broadcast.
-- 2) admin_usage_stats(): one jsonb blob of engagement numbers for the
--    admin-web "Usage" tab (DAU/WAU/MAU from profiles.last_active_at,
--    signups, and content counts).

create or replace function public.admin_notify_user(
  p_user_id uuid, p_title text, p_body text
) returns integer
language plpgsql security definer set search_path to 'public','auth'
as $fn$
declare
  v_count integer := 0;
  v_title text := nullif(btrim(coalesce(p_title,'')),'');
  v_body  text := nullif(btrim(coalesce(p_body,'')),'');
begin
  perform public.assert_super_admin();
  if v_title is null or v_body is null then
    raise exception 'Title and message are both required.';
  end if;
  insert into public.notifications (user_id, title, body, type, reference_type)
  select p.id, v_title, v_body, 'admin_direct', 'announcement'
    from public.profiles p
   where p.id = p_user_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$fn$;

grant execute on function public.admin_notify_user(uuid, text, text) to authenticated;

create or replace function public.admin_usage_stats()
returns jsonb
language plpgsql security definer set search_path to 'public','auth'
as $fn$
declare result jsonb;
begin
  perform public.assert_super_admin();
  select jsonb_build_object(
    'total_users',      (select count(*) from public.profiles),
    'new_1d',           (select count(*) from public.profiles where created_at > now() - interval '1 day'),
    'new_7d',           (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'new_30d',          (select count(*) from public.profiles where created_at > now() - interval '30 days'),
    'active_1d',        (select count(*) from public.profiles where last_active_at > now() - interval '1 day'),
    'active_7d',        (select count(*) from public.profiles where last_active_at > now() - interval '7 days'),
    'active_30d',       (select count(*) from public.profiles where last_active_at > now() - interval '30 days'),
    'banned',           (select count(*) from public.profiles where coalesce(is_banned,false)),
    'posts',            (select count(*) from public.posts),
    'stories',          (select count(*) from public.stories),
    'events',           (select count(*) from public.events),
    'jobs',             (select count(*) from public.jobs),
    'products',         (select count(*) from public.products),
    'prayers',          (select count(*) from public.prayers),
    'messages',         (select count(*) from public.messages),
    'conversations',    (select count(*) from public.conversations),
    'friendships',      (select count(*) from public.friendships where status = 'accepted'),
    'church_follows',   (select count(*) from public.church_followers),
    'survey_responses', (select count(*) from public.signup_surveys)
  ) into result;
  return result;
end;
$fn$;

grant execute on function public.admin_usage_stats() to authenticated;
