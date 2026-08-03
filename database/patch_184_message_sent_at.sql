-- patch_184 (#11): a message is timed by when it was SENT, not received.
--
-- `created_at` defaults to now() at INSERT, i.e. the moment the row reached
-- the server. Online that is within milliseconds of tapping send, so the
-- bug is invisible in normal use — but a message composed offline sits in
-- the Hive outbox until connectivity returns and is only inserted then.
-- A note written at 21:00 and flushed at 07:40 the next morning was
-- displayed, and ORDERED, as 07:40. It jumped to the bottom of the thread,
-- out of sequence with the replies it was answering.
--
-- WhatsApp's behaviour, which is what was asked for: the bubble and the
-- chat list show the sender's send time and messages order by it. Only the
-- push stays tied to delivery — a notification is about arrival, so it
-- correctly fires when the row lands.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS sent_at timestamptz;

-- Existing history: the two were the same thing before this column
-- existed, so created_at is the honest answer for every old row.
UPDATE public.messages SET sent_at = created_at WHERE sent_at IS NULL;

ALTER TABLE public.messages
  ALTER COLUMN sent_at SET DEFAULT now();
ALTER TABLE public.messages
  ALTER COLUMN sent_at SET NOT NULL;

-- Ordering index. The thread query sorts by this now, and without it every
-- conversation open becomes a sort over the whole partition.
CREATE INDEX IF NOT EXISTS messages_conversation_sent_at_idx
  ON public.messages (conversation_id, sent_at);

-- The client supplies this value, so it cannot be trusted as given.
--
-- Two things have to be impossible. A message must never claim to have
-- been sent AFTER it arrived — a device clock running fast would otherwise
-- pin it to the bottom of every thread forever. And it must never claim to
-- be arbitrarily old: a badly-wrong clock (or a mischievous client) could
-- bury a message at the top of a conversation's history where nobody would
-- see it arrive. Fourteen days is comfortably longer than any real outbox
-- wait and short enough to keep that harmless.
CREATE OR REPLACE FUNCTION public.clamp_message_sent_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.sent_at := LEAST(
    GREATEST(COALESCE(NEW.sent_at, now()), now() - interval '14 days'),
    now()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_clamp_sent_at ON public.messages;
CREATE TRIGGER messages_clamp_sent_at
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.clamp_message_sent_at();

-- The conversation list sorts on this, so it has to move with the bubbles
-- or a thread whose newest message was sent offline sorts to the wrong
-- place in the inbox.
COMMENT ON COLUMN public.messages.sent_at IS
  'When the SENDER composed it (clamped to <= arrival). Display + ordering '
  'use this; created_at remains the true arrival time and is what the push '
  'is tied to.';
-- my_inbox_previews, revised for #11: the inbox preview must show — and be
-- picked by — the time the message was SENT.
--
-- `DISTINCT ON ... ORDER BY created_at DESC` chose the latest ARRIVAL, so a
-- thread's preview could be an older message that merely landed last after
-- an outbox flush. `sent_at` is added to the result so the inbox tile can
-- stamp it correctly too.
-- Dropped first: adding a column to RETURNS TABLE changes the return type,
-- which CREATE OR REPLACE refuses.
DROP FUNCTION IF EXISTS public.my_inbox_previews();

CREATE FUNCTION public.my_inbox_previews()
RETURNS TABLE(
  conversation_id bigint,
  content         text,
  message_type    text,
  created_at      timestamptz,
  sent_at         timestamptz,
  sender_id       uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (m.conversation_id)
         m.conversation_id, m.content, m.message_type,
         m.created_at, m.sent_at, m.sender_id
    FROM public.messages m
   WHERE m.conversation_id IN (
           SELECT c.id FROM public.conversations c
            WHERE c.participant_a_id = auth.uid()
               OR c.participant_b_id = auth.uid()
           UNION
           SELECT cm.conversation_id FROM public.conversation_members cm
            WHERE cm.user_id = auth.uid() AND cm.left_at IS NULL
         )
     AND NOT EXISTS (
           SELECT 1 FROM public.hidden_messages h
            WHERE h.message_id = m.id AND h.user_id = auth.uid()
         )
   ORDER BY m.conversation_id, m.sent_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.my_inbox_previews() FROM public;
GRANT EXECUTE ON FUNCTION public.my_inbox_previews() TO authenticated;
