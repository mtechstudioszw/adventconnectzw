-- patch_137: voice-note play receipts. The SENDER can see whether the
-- recipient has played their voice note (WhatsApp's blue mic).
--
-- A recipient (a conversation member who is NOT the sender) marks a voice
-- message played via mark_voice_played(). RLS on messages is owner/participant
-- scoped, so we use a SECURITY DEFINER function with an explicit membership
-- check rather than opening UPDATE on messages to non-senders.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS voice_played_at timestamptz;

CREATE OR REPLACE FUNCTION public.mark_voice_played(p_message_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.messages m
     SET voice_played_at = now()
   WHERE m.id = p_message_id
     AND m.message_type = 'voice'
     AND m.sender_id <> auth.uid()        -- only the listener marks it
     AND m.voice_played_at IS NULL        -- first play only
     AND EXISTS (
       SELECT 1 FROM public.conversation_members cm
        WHERE cm.conversation_id = m.conversation_id
          AND cm.user_id = auth.uid()
          AND cm.left_at IS NULL
     );
END;
$$;

REVOKE ALL ON FUNCTION public.mark_voice_played(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_voice_played(bigint) TO authenticated;
