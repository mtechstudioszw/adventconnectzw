-- =====================================================================
--  PATCH 119 — my_friends() : the signed-in user's accepted friends as
--  display rows (id, name, photo, church). SECURITY DEFINER so friends
--  show with their real name/photo even when their profile isn't publicly
--  discoverable (mirrors pending_friend_requests). Powers the friends-only
--  "New chat" picker and the friends-only group member picker.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.my_friends()
 RETURNS TABLE(friend_id text, full_name text, profile_photo_url text, church_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT
    other_id::text,
    COALESCE(NULLIF(btrim(p.full_name), ''), 'Member'),
    p.profile_photo_url,
    c.name
  FROM (
    SELECT CASE WHEN f.requester_id = auth.uid()
                THEN f.addressee_id ELSE f.requester_id END AS other_id
    FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
  ) fr
  LEFT JOIN public.profiles p ON p.id = fr.other_id
  LEFT JOIN public.churches  c ON c.id = p.church_id
  ORDER BY COALESCE(NULLIF(btrim(p.full_name), ''), 'Member');
$function$;
