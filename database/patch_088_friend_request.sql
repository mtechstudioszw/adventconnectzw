-- =====================================================================
--  PATCH 088 — robust friend requests + decline notification
--
--  Bugs: a blind INSERT created reverse-duplicate rows (A→B and B→A, so
--  both saw a pending request from the other), re-requesting after a
--  decline failed, and tapping "Add friend" on someone who already
--  requested you said "could not send". This RPC is idempotent:
--    * already accepted          -> return as-is
--    * incoming pending (they→me) -> ACCEPT it (become friends)
--    * outgoing pending (me→they) -> return as-is
--    * declined (either way)      -> reset to pending with me as requester
--    * none                       -> insert pending
--  Plus a trigger that notifies the requester when a request is declined.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee UUID)
RETURNS public.friendships
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me  UUID := auth.uid();
  v_row public.friendships;
BEGIN
  IF v_me IS NULL OR v_me = p_addressee THEN
    RAISE EXCEPTION 'Invalid friend request.';
  END IF;

  SELECT * INTO v_row FROM public.friendships
   WHERE (requester_id = v_me AND addressee_id = p_addressee)
      OR (requester_id = p_addressee AND addressee_id = v_me)
   LIMIT 1;

  IF v_row.id IS NOT NULL THEN
    IF v_row.status = 'accepted' THEN
      RETURN v_row;
    ELSIF v_row.status = 'pending' AND v_row.addressee_id = v_me THEN
      UPDATE public.friendships SET status = 'accepted'
       WHERE id = v_row.id RETURNING * INTO v_row;
      RETURN v_row;
    ELSIF v_row.status = 'pending' THEN
      RETURN v_row;
    ELSE -- declined: re-open as a fresh pending request from me
      UPDATE public.friendships
         SET requester_id = v_me, addressee_id = p_addressee, status = 'pending'
       WHERE id = v_row.id RETURNING * INTO v_row;
      RETURN v_row;
    END IF;
  END IF;

  INSERT INTO public.friendships (requester_id, addressee_id, status)
  VALUES (v_me, p_addressee, 'pending') RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_friend_request(UUID) TO authenticated;

-- Notify the requester when their request is declined.
CREATE OR REPLACE FUNCTION public.notify_friend_declined()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'declined' THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    VALUES (
      NEW.requester_id, 'Friend request',
      (SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone')
         FROM public.profiles WHERE id = NEW.addressee_id)
        || ' declined your friend request',
      'social', NEW.id::text, 'friendship');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_friend_declined ON public.friendships;
CREATE TRIGGER trg_notify_friend_declined
  AFTER UPDATE ON public.friendships
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_friend_declined();
