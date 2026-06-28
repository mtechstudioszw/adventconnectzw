-- patch_150_engagement_notifications.sql
-- Like & comment notifications: when someone interacts with YOUR content,
-- drop a row into public.notifications. The existing
-- "notify-fcm-on-notification-insert" webhook turns each row into a push
-- automatically, so no edge-function change is needed — the new `type`
-- values (post_like / post_comment / comment_reply / comment_like) fall
-- through mapTypeToCategory() as "send by default", same as friend requests.
--
-- Recipients:
--   * post_like      -> the post's author (someone liked their post)
--   * post_comment   -> the post's author (top-level comment on their post)
--   * comment_reply  -> the parent comment's author (reply to their comment)
--   * comment_like   -> the comment's author (someone liked their comment)
--
-- Self-actions never notify (you liking your own post, replying to
-- yourself, etc.). reference_type is always 'post' with reference_id =
-- the post id, so a tap opens the post's discussion (comments sheet).

-- ---------------------------------------------------------------------
-- Helper: a friendly display name for the actor.
-- ---------------------------------------------------------------------
create or replace function public.notif_actor_name(p_user uuid)
returns text language sql stable as $$
  select coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), 'Someone')
  from public.profiles where id = p_user;
$$;

-- ---------------------------------------------------------------------
-- 1) Someone LIKED your post
-- ---------------------------------------------------------------------
create or replace function public.notify_post_like()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_author uuid;
  v_snip   text;
  v_actor  text;
begin
  select author_id, left(coalesce(body, ''), 60)
    into v_author, v_snip
  from public.posts where id = new.post_id;

  -- No author, or you liked your own post -> nothing to do.
  if v_author is null or v_author = new.user_id then
    return new;
  end if;

  v_actor := public.notif_actor_name(new.user_id);

  insert into public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  values (
    v_author,
    'New like',
    v_actor || ' liked your post' ||
      case when v_snip <> '' then ': “' || v_snip || '”' else '.' end,
    'post_like',
    new.post_id::text,
    'post'
  );
  return new;
end; $$;

drop trigger if exists trg_notify_post_like on public.post_likes;
create trigger trg_notify_post_like
  after insert on public.post_likes
  for each row execute function public.notify_post_like();

-- ---------------------------------------------------------------------
-- 2) Someone COMMENTED on your post / REPLIED to your comment
-- ---------------------------------------------------------------------
create or replace function public.notify_post_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_post_author uuid;
  v_parent_author uuid;
  v_actor text;
  v_snip  text;
begin
  v_actor := public.notif_actor_name(new.author_id);
  v_snip  := left(coalesce(new.body, ''), 60);

  if new.parent_comment_id is null then
    -- Top-level comment -> tell the post's author.
    select author_id into v_post_author
    from public.posts where id = new.post_id;

    if v_post_author is not null and v_post_author <> new.author_id then
      insert into public.notifications
        (user_id, title, body, type, reference_id, reference_type)
      values (
        v_post_author,
        'New comment',
        v_actor || ' commented on your post' ||
          case when v_snip <> '' then ': “' || v_snip || '”' else '.' end,
        'post_comment',
        new.post_id::text,
        'post'
      );
    end if;
  else
    -- Reply -> tell the parent comment's author.
    select author_id into v_parent_author
    from public.post_comments where id = new.parent_comment_id;

    if v_parent_author is not null and v_parent_author <> new.author_id then
      insert into public.notifications
        (user_id, title, body, type, reference_id, reference_type)
      values (
        v_parent_author,
        'New reply',
        v_actor || ' replied to your comment' ||
          case when v_snip <> '' then ': “' || v_snip || '”' else '.' end,
        'comment_reply',
        new.post_id::text,
        'post'
      );
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists trg_notify_post_comment on public.post_comments;
create trigger trg_notify_post_comment
  after insert on public.post_comments
  for each row execute function public.notify_post_comment();

-- ---------------------------------------------------------------------
-- 3) Someone LIKED your comment (positive reaction only; value = 1)
-- ---------------------------------------------------------------------
create or replace function public.notify_comment_like()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_author uuid;
  v_post   uuid;
  v_actor  text;
begin
  -- Only notify on a fresh "like". On UPDATE, only when it newly became a
  -- like (was non-positive before) so toggling/touching doesn't re-notify.
  if new.value <> 1 then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.value = 1 then
    return new;
  end if;

  select author_id, post_id into v_author, v_post
  from public.post_comments where id = new.comment_id;

  if v_author is null or v_author = new.user_id then
    return new;
  end if;

  v_actor := public.notif_actor_name(new.user_id);

  insert into public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  values (
    v_author,
    'New like',
    v_actor || ' liked your comment.',
    'comment_like',
    v_post::text,
    'post'
  );
  return new;
end; $$;

drop trigger if exists trg_notify_comment_like on public.post_comment_reactions;
create trigger trg_notify_comment_like
  after insert or update on public.post_comment_reactions
  for each row execute function public.notify_comment_like();
