-- patch_212: a TRUE count of who is waiting to play a live match.
--
-- Founder, 18 Aug 2026: *"the quiz live banner is lying tt some people
-- online to play quiz live when one will be in the lobby"*.
--
-- He is right, and the code already knew it. Both live-match strips — the
-- one on Home and the one in the lobby — took their number from the app-wide
-- `online_users` presence channel, which counts anyone with the app open:
-- somebody reading the feed, in a chat, watching a video. The wording was
-- softened twice to say "in the app · challenge one" rather than "waiting to
-- play", and the comment in `_LiveMatchStrip` says in as many words that a
-- real count "needs a server-side count of open queue entries; see TODO.md.
-- Do not fake it from this number."
--
-- Softer wording was never going to fix it. A green bolt on a strip that
-- appears BECAUSE people are around reads as "there is a game here", and
-- then the arena is empty. This is that server-side count, so the strip can
-- stop guessing.
--
-- What counts as waiting is exactly what `quiz_match_find` will actually
-- pair you with — same status, same 2-minute freshness window, same "not
-- me" — so a member who taps because the strip said 1 is waiting gets that
-- match. Any looser definition puts us straight back where we started.

CREATE OR REPLACE FUNCTION public.quiz_arena_waiting()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::integer
    FROM public.quiz_matches
   WHERE status = 'open'
     AND player_a <> auth.uid()
     AND created_at > now() - interval '2 minutes';
$$;

COMMENT ON FUNCTION public.quiz_arena_waiting() IS
  'How many OTHER players are sitting in the live-match queue right now, '
  'using the same window quiz_match_find pairs on. Never derive this from '
  'presence: presence counts everyone with the app open.';

-- REVOKE FROM public is not enough on Supabase — it grants EXECUTE to anon
-- and authenticated explicitly. Verify with has_function_privilege.
REVOKE ALL ON FUNCTION public.quiz_arena_waiting() FROM public;
REVOKE ALL ON FUNCTION public.quiz_arena_waiting() FROM anon;
GRANT EXECUTE ON FUNCTION public.quiz_arena_waiting() TO authenticated;
