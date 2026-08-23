-- =====================================================================
--  PATCH 227 — Notes to self has never shown a delivered/read tick
--
--  Reported 23 Aug 2026: "the tick system doesn't work for notes to
--  self".
--
--  ## The bug
--
--  Both receipt RPCs carry the same guard:
--
--      AND m.sender_id <> v_user
--
--  which is correct and necessary for an ordinary 1:1 chat — without it
--  you would mark your OWN outgoing messages as read and light up your
--  own tick the instant you opened the thread, which is a lie about
--  whether the other person has seen anything.
--
--  In a self-chat that same guard is unsatisfiable. Notes to self is a
--  conversation where `participant_a_id = participant_b_id = you`, so
--  every message in it has `sender_id = you`. The predicate is therefore
--  ALWAYS false, the UPDATE matches zero rows every time, and
--  `delivered_at` / `read` stay NULL and FALSE for the life of the
--  message. The ticks are not wrong — they were never written at all.
--
--  This is the mirror image of the reason the guard exists. There, you
--  are not the recipient so you must not mark it read. Here, you are the
--  ONLY recipient, so nobody else ever will.
--
--  ## The fix
--
--  Exempt self-chats from the guard, by asking the conversation rather
--  than the message:
--
--      AND (m.sender_id <> v_user OR c.participant_a_id = c.participant_b_id)
--
--  `c` is already joined in both functions for the membership check, so
--  this costs nothing and needs no new lookup. Ordinary chats are
--  completely unaffected: for them `participant_a_id <> participant_b_id`,
--  the right-hand side is false, and the original guard stands exactly as
--  before.
--
--  Note this is deliberately NOT `m.sender_id = v_user AND <self chat>`,
--  and not a check on the message. The property that makes marking safe
--  belongs to the CONVERSATION — "am I the only participant?" — and
--  reading it off the message would re-introduce the same confusion
--  between "who sent this" and "who is entitled to receipt it".
-- =====================================================================

CREATE OR REPLACE FUNCTION public.mark_conversation_read(
  p_conversation_id bigint,
  p_with_timestamp boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user UUID := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to mark messages read.';
  END IF;
  UPDATE public.messages m
     SET "read"  = TRUE,
         read_at = CASE
                     WHEN p_with_timestamp AND m.read_at IS NULL
                       THEN NOW()
                     ELSE m.read_at
                   END,
         -- Also set delivered_at if we somehow read before a delivery
         -- ping arrived (e.g. cold-start straight into the chat).
         delivered_at = COALESCE(m.delivered_at, NOW())
    FROM public.conversations c
   WHERE m.conversation_id = p_conversation_id
     AND m.conversation_id = c.id
     -- Self-chat exemption — see the header. In Notes to self you are
     -- both participants, so `sender_id <> v_user` never matched and the
     -- ticks were never written.
     AND (m.sender_id <> v_user
          OR c.participant_a_id = c.participant_b_id)
     AND m."read" = FALSE
     AND (c.participant_a_id = v_user OR c.participant_b_id = v_user);
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_conversation_delivered(
  p_conversation_id bigint
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user UUID := auth.uid();
  v_count INTEGER;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in to mark messages delivered.';
  END IF;

  UPDATE public.messages m
     SET delivered_at = NOW()
    FROM public.conversations c
   WHERE m.conversation_id = p_conversation_id
     AND m.conversation_id = c.id
     -- Same exemption as mark_conversation_read above. These two must
     -- stay in step: a delivered tick that can never be written makes
     -- the read tick unreachable too, because the UI advances ✓ → ✓✓.
     AND (m.sender_id <> v_user
          OR c.participant_a_id = c.participant_b_id)
     AND m.delivered_at IS NULL
     AND (c.participant_a_id = v_user OR c.participant_b_id = v_user);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

-- ---------------------------------------------------------------------
--  Backfill: every note anyone has ever written to themselves is sitting
--  on a single grey tick. Nothing will ever mark them, because the code
--  that would have is the code this patch just fixed — so they need one
--  explicit sweep.
--
--  Restricted to genuine self-chats, so it cannot touch a real
--  conversation's receipts.
-- ---------------------------------------------------------------------
UPDATE public.messages m
   SET delivered_at = COALESCE(m.delivered_at, m.created_at),
       read_at      = COALESCE(m.read_at, m.created_at),
       "read"       = TRUE
  FROM public.conversations c
 WHERE m.conversation_id = c.id
   AND c.participant_a_id = c.participant_b_id
   AND (m."read" = FALSE OR m.delivered_at IS NULL);
