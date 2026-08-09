-- =====================================================================
--  patch_194 — accepting a friend request left a second request behind
--
--  Reported as "you accept a friend request twice".
--
--  ## What happened
--
--  Somebody who is not your friend yet can do two things: send a friend
--  request, and send you one message. Do both and you appear twice in the
--  Requests view — once under "Friend requests", once under "Message
--  requests".
--
--  The client already knew that, and hid the second one:
--
--      final friendIds = _friendRequests.map((r) => r.requesterId).toSet();
--      final list = _requests.where((c) => !friendIds.contains(c.otherUserId))
--
--  But it hides the message request only WHILE the friend request is in
--  the list. Accepting removes it from that list, so on the very next
--  frame the suppressed row renders — same face, same name, another
--  Accept button. To the member that is the identical request appearing a
--  second time and demanding to be accepted again.
--
--  Underneath, the conversation really was still `pending`.
--  `conversations_auto_accept_friends` (patch_032) covers this, but only
--  BEFORE INSERT — it decides at the moment a conversation is created.
--  patch_032 also promoted the existing backlog, but that was a one-shot
--  UPDATE, not a trigger. Nothing has ever handled the ordering that
--  actually happens in practice: message first, friendship accepted
--  after. The conversation stayed pending for ever.
--
--  ## The fix
--
--  A trigger on `friendships`: becoming friends promotes any pending
--  conversation between the pair, which is what the member's tap already
--  means. Server-side rather than in the Requests screen, because there
--  are four places that accept a friend request — the Requests view, the
--  home suggestion rail, a member's profile, and the chat screen — and
--  the fix has to hold for all of them.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.friendships_promote_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NEW.status <> 'accepted' THEN
    RETURN NEW;
  END IF;

  UPDATE public.conversations c
     SET request_status = 'accepted'
   WHERE c.request_status = 'pending'
     AND (
       (c.participant_a_id = NEW.requester_id
          AND c.participant_b_id = NEW.addressee_id)
       OR
       (c.participant_a_id = NEW.addressee_id
          AND c.participant_b_id = NEW.requester_id)
     );

  RETURN NEW;
END;
$$;

-- AFTER, not BEFORE: this touches a different table, so there is nothing
-- to hand back on NEW and no reason to sit in the write path of the row
-- being changed.
--
-- INSERT is included because a friendship can be born accepted (an
-- auto-accept path, or a re-friend), and UPDATE carries the ordinary
-- pending → accepted transition. The WHEN clause keeps declines and
-- no-op updates out of the function entirely.
DROP TRIGGER IF EXISTS trg_friendships_promote_conversation
  ON public.friendships;
CREATE TRIGGER trg_friendships_promote_conversation
  AFTER INSERT OR UPDATE OF status ON public.friendships
  FOR EACH ROW
  WHEN (NEW.status = 'accepted')
  EXECUTE FUNCTION public.friendships_promote_conversation();

-- Catch up anything already in this state. Expected to be 0 or small —
-- patch_032 cleared the backlog once — but a pair who became friends
-- after that patch and before this one is still stuck.
UPDATE public.conversations c
   SET request_status = 'accepted'
 WHERE c.request_status = 'pending'
   AND EXISTS (
     SELECT 1
       FROM public.friendships f
      WHERE f.status = 'accepted'
        AND (
          (f.requester_id = c.participant_a_id
             AND f.addressee_id = c.participant_b_id)
          OR
          (f.requester_id = c.participant_b_id
             AND f.addressee_id = c.participant_a_id)
        )
   );
