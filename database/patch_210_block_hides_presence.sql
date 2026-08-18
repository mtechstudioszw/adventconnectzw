-- =====================================================================
--  PATCH 210 — blocking hides presence, both directions
--
--  THE GAP
--
--  patch_200/201 made block symmetric for posts, stories, prayers,
--  search and finally `profiles` itself. Every one of those is a
--  DATABASE read, so a policy could fix them.
--
--  Presence is not. "Online" comes from a Supabase Realtime presence
--  channel (`online_users`) that every signed-in client joins and
--  broadcasts itself on. There is no row, so there is no RLS, so
--  blocking someone has never taken your green dot away from them:
--
--    * you block them  -> their profile reads "unavailable", their photo
--                         and about and cover are gone (patch_201) ...
--                         and the chat header still says "Online".
--
--  `last seen` was already covered by accident — PresenceService reads
--  `profiles.last_active_at`, which patch_201 closed — so the reported
--  symptom is specifically the live dot, plus the denormalised name and
--  photo the conversation row carries.
--
--  THE FIX
--
--  A client cannot filter a roster it has no opinion about, so give it
--  one: the set of user ids it is in a block relationship with, in
--  EITHER direction. PresenceService loads it once per session and
--  treats those ids as permanently offline.
--
--  WHY BOTH DIRECTIONS. Returning only "who blocked me" would leave the
--  blocker still watching the blocked person's dot — which is exactly
--  the one-directional mistake patch_201 was written to undo. Block
--  means neither of you sees the other, and one set expresses that.
--
--  ON THE OBVIOUS OBJECTION — doesn't this tell the blocked user they
--  were blocked? No more than the app already does: their target's
--  profile is already "This account is unavailable", their posts already
--  vanished, and their messages already fail silently. The set is never
--  rendered and never named; it only removes dots.
--
--  SECURITY DEFINER because `blocked_users` RLS deliberately hides the
--  other person's rows — that is the same reason is_blocked_by() exists.
--  Returns ONLY ids in a relationship with the caller: it cannot be used
--  to ask about anyone else, because auth.uid() is the only input.
--
--  IDEMPOTENT: yes.
-- =====================================================================


CREATE OR REPLACE FUNCTION public.presence_hidden_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT b.blocked_id AS id
    FROM public.blocked_users b
   WHERE b.blocker_id = auth.uid()
  UNION
  SELECT b.blocker_id AS id
    FROM public.blocked_users b
   WHERE b.blocked_id = auth.uid();
$function$;

REVOKE ALL ON FUNCTION public.presence_hidden_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presence_hidden_ids() TO authenticated;
