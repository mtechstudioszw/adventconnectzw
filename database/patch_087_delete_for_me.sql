-- =====================================================================
--  PATCH 087 — "Delete for me" (per-user hidden messages)
--
--  Delete for everyone = the existing soft-delete tombstone (own msgs).
--  Delete for me = hide the message for the caller only (works on anyone's
--  message). Multi-select delete uses this so it can include the other
--  person's messages.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.hidden_messages (
  user_id    UUID   NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message_id BIGINT NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);
ALTER TABLE public.hidden_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hidden_messages_own ON public.hidden_messages;
CREATE POLICY hidden_messages_own ON public.hidden_messages
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.hide_messages(p_ids BIGINT[])
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.hidden_messages (user_id, message_id)
  SELECT auth.uid(), unnest(p_ids)
  ON CONFLICT DO NOTHING;
$$;
GRANT EXECUTE ON FUNCTION public.hide_messages(BIGINT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.hidden_message_ids(p_conv BIGINT)
RETURNS SETOF BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT h.message_id
    FROM public.hidden_messages h
    JOIN public.messages m ON m.id = h.message_id
   WHERE h.user_id = auth.uid() AND m.conversation_id = p_conv;
$$;
GRANT EXECUTE ON FUNCTION public.hidden_message_ids(BIGINT) TO authenticated;
