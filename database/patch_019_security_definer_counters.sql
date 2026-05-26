-- =====================================================================
--  PATCH 019 — SECURITY DEFINER on counter-bump triggers
--
--  WHY:
--   bump_prayer_count, bump_church_follower_count, bump_event_rsvp_count,
--   and update_conversation_on_message all UPDATE rows on tables whose
--   RLS UPDATE policy is "auth.uid() = author_id / poster_id". Those
--   functions were created with the default SECURITY INVOKER, so when
--   user B triggers them by writing to prayer_responses / event_rsvps
--   / church_followers / messages for content owned by user A, the
--   trigger's UPDATE silently affects 0 rows (RLS filters it out) and
--   the denormalised counter never increments.
--
--   Visible symptoms in the app:
--     - Praying for someone else's prayer doesn't bump prayer_count.
--     - Commenting on someone else's prayer doesn't bump comment_count.
--     - Following someone else's church doesn't bump follower_count.
--     - RSVP'ing to a friend's event doesn't bump rsvp_count.
--     - Sending a message doesn't refresh the inbox preview row when
--       the recipient (not sender) viewed the conversations table last.
--
--   SECURITY DEFINER plus SET search_path = public makes these
--   functions run as the function owner (a superuser by default in
--   Supabase) so the UPDATE bypasses RLS for the counter columns.
--   The integrity guarantees (you can only insert your own response
--   etc.) are still enforced by the INSERT policies on the source
--   tables — this just allows the side-effect to land.
--
--  PREREQUISITES: schema.sql already run.
--  IDEMPOTENT:    yes — CREATE OR REPLACE on each function.
-- =====================================================================


CREATE OR REPLACE FUNCTION public.bump_prayer_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.response_type = 'praying') THEN
    UPDATE public.prayers SET prayer_count = prayer_count + 1 WHERE id = NEW.prayer_id;
  ELSIF (TG_OP = 'INSERT' AND NEW.response_type = 'message') THEN
    UPDATE public.prayers SET comment_count = comment_count + 1 WHERE id = NEW.prayer_id;
  ELSIF (TG_OP = 'DELETE' AND OLD.response_type = 'praying') THEN
    UPDATE public.prayers SET prayer_count = GREATEST(prayer_count - 1, 0) WHERE id = OLD.prayer_id;
  ELSIF (TG_OP = 'DELETE' AND OLD.response_type = 'message') THEN
    UPDATE public.prayers SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = OLD.prayer_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


CREATE OR REPLACE FUNCTION public.bump_church_follower_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE public.churches SET follower_count = follower_count + 1 WHERE id = NEW.church_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE public.churches SET follower_count = GREATEST(follower_count - 1, 0) WHERE id = OLD.church_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


CREATE OR REPLACE FUNCTION public.bump_event_rsvp_count()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.status = 'going') THEN
    UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
  ELSIF (TG_OP = 'DELETE' AND OLD.status = 'going') THEN
    UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = OLD.event_id;
  ELSIF (TG_OP = 'UPDATE' AND OLD.status <> NEW.status) THEN
    IF NEW.status = 'going' THEN
      UPDATE public.events SET rsvp_count = rsvp_count + 1 WHERE id = NEW.event_id;
    ELSIF OLD.status = 'going' THEN
      UPDATE public.events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE id = NEW.event_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- This one also writes to conversations.last_message_at / last_sender_id.
-- The conversations UPDATE policy permits only participants — and the
-- message sender IS one — so this was technically working for outbound,
-- but the recipient-side update (e.g., delivered receipt later writing
-- the same conversation row from the other participant's session) needs
-- the same definer pattern.
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.conversations
     SET last_message    = NEW.content,
         last_message_at = NEW.created_at,
         last_sender_id  = NEW.sender_id,
         updated_at      = NOW()
   WHERE id = NEW.conversation_id;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
