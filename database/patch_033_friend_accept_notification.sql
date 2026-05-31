-- =====================================================================
--  PATCH 033 — Notify the requester when a friend request is accepted
--
--  WHY: User spec (2026-05-31): "Once you accept a friend request the
--       person who sent the request should get a notification that
--       user A accepted your friend request." Today only the addressee
--       gets a notification (the inbound request itself, via patch_029
--       trg_friendships_notify_addressee). When the addressee accepts,
--       the requester hears nothing.
--
--  WHAT: AFTER UPDATE trigger on friendships that fires once when
--        status moves from anything-other-than-'accepted' to
--        'accepted'. Writes a notifications row addressed to the
--        requester with reference_type='friendship' so the push
--        pipeline + in-app centre can route a tap straight to the
--        accepter's profile.
--
--  IDEMPOTENT: yes — CREATE OR REPLACE + DROP/CREATE TRIGGER.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.friendships_notify_accepter()
RETURNS TRIGGER AS $$
DECLARE
  v_accepter_name TEXT;
BEGIN
  -- Only fire on the actual pending -> accepted transition.
  IF NEW.status <> 'accepted' THEN RETURN NEW; END IF;
  IF OLD.status = 'accepted'  THEN RETURN NEW; END IF;

  -- The accepter is the addressee of the original request.
  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), 'Someone')
    INTO v_accepter_name
    FROM public.profiles p
    WHERE p.id = NEW.addressee_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    NEW.requester_id,
    'Friend request accepted',
    v_accepter_name || ' accepted your friend request.',
    'friend_accepted',
    NEW.id::text,
    'friendship'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_friendships_notify_accepter
  ON public.friendships;
CREATE TRIGGER trg_friendships_notify_accepter
  AFTER UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.friendships_notify_accepter();
