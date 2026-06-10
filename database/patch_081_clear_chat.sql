-- =====================================================================
--  PATCH 081 — "Clear chat" (per-user)
--
--  Clearing a chat hides all current messages for the CALLER only
--  (WhatsApp parity) — it does not delete them for the other person.
--  We stamp cleared_at on the per-user conversation_state row; the client
--  then only fetches messages created after that time.
-- =====================================================================

ALTER TABLE public.conversation_state
  ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.clear_conversation(p_conversation BIGINT)
RETURNS VOID AS $$
  INSERT INTO public.conversation_state (user_id, conversation_id, cleared_at)
  VALUES (auth.uid(), p_conversation, now())
  ON CONFLICT (user_id, conversation_id)
  DO UPDATE SET cleared_at = now();
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;
REVOKE ALL ON FUNCTION public.clear_conversation(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_conversation(BIGINT) TO authenticated;
