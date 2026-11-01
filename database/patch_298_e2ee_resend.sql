-- =====================================================================
--  PATCH 298 — new encrypted messages always open ("retry receipts")
--  STATUS: not yet applied. Run AFTER patch_294, BEFORE patch_295.
--
--  Owner, 1 Nov 2026: "leave it as 'waiting for this message' — it's
--  fine for old messages, but for new ones don't."
--
--  A NEW message could still be unreadable on the phone it reached:
--    * a group message whose sender key hadn't arrived yet;
--    * a member with two phones — only the newest got the message;
--    * your own message, sent from your other phone.
--  Signal fixes this with "retry receipts": the phone that can't open a
--  message asks, and the sender's phone (which still has the text)
--  re-encrypts that one message for that one device. Same here:
--
--    e2ee_request_resend   the reader's phone asks. Only for messages
--                          sent AFTER this phone registered its keys —
--                          older ones stay "Waiting for this message",
--                          as the owner asked.
--    e2ee_pending_resends  the sender's phone collects requests.
--    e2ee_fulfill_resend   …and answers with a per-device copy.
--    e2ee_copies_for       the reader's phone picks the copy up.
--
--  The server only ever holds ciphertext. A copy is encrypted to one
--  device with that device's own session, like any message.
--
--  Also fixes a key leak: the app claimed (used up) one of the
--  recipient's one-time prekeys on EVERY encrypted send, even with a
--  session already open. e2ee_latest_device lets it skip the claim.
--  claim_prekey_bundle_for claims for one specific device (needed for
--  copies to a member's other phone).
--
--  CLAUDE.md checklist: no profiles change; no triggers. New tables have
--  RLS on and NO policies/grants: they are reached only through these
--  SECURITY DEFINER functions.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.e2ee_resend_requests (
  message_id       bigint NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  requester_user   uuid   NOT NULL,
  requester_device integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  fulfilled_at     timestamptz,
  PRIMARY KEY (message_id, requester_user, requester_device)
);
CREATE INDEX IF NOT EXISTS e2ee_resend_open_idx
  ON public.e2ee_resend_requests (message_id) WHERE fulfilled_at IS NULL;

CREATE TABLE IF NOT EXISTS public.e2ee_message_copies (
  message_id       bigint NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  recipient_user   uuid   NOT NULL,
  recipient_device integer NOT NULL,
  sender_device    integer NOT NULL,
  ciphertext       text   NOT NULL,
  ciphertext_type  integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, recipient_user, recipient_device)
);

ALTER TABLE public.e2ee_resend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.e2ee_message_copies  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.e2ee_resend_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.e2ee_message_copies  FROM PUBLIC, anon, authenticated;

-- Can the caller read this message's conversation right now?
CREATE OR REPLACE FUNCTION public.e2ee_can_read_message(p_message bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.messages m
      JOIN public.conversations c ON c.id = m.conversation_id
     WHERE m.id = p_message
       AND (c.participant_a_id = auth.uid()
            OR c.participant_b_id = auth.uid()
            OR EXISTS (SELECT 1 FROM public.conversation_members cm
                        WHERE cm.conversation_id = c.id
                          AND cm.user_id = auth.uid()
                          AND cm.left_at IS NULL))
  );
$function$;
REVOKE EXECUTE ON FUNCTION public.e2ee_can_read_message(bigint) FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.e2ee_latest_device(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN public.is_blocked_by(p_user) THEN NULL ELSE (
    SELECT d.device_id FROM public.e2ee_devices d
     WHERE d.user_id = p_user
     ORDER BY d.last_seen_at DESC
     LIMIT 1) END;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_latest_device(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_prekey_bundle_for(p_user uuid, p_device integer)
RETURNS TABLE(device_id integer, registration_id integer, identity_key text,
              signed_key_id integer, signed_key text, signed_sig text,
              prekey_id integer, prekey text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_prekey RECORD;
BEGIN
  IF public.is_blocked_by(p_user) THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.e2ee_devices d
                  WHERE d.user_id = p_user AND d.device_id = p_device) THEN
    RETURN;
  END IF;

  UPDATE public.e2ee_prekeys k
     SET claimed_at = NOW()
   WHERE (k.user_id, k.device_id, k.key_id) = (
     SELECT s.user_id, s.device_id, s.key_id
       FROM public.e2ee_prekeys s
      WHERE s.user_id = p_user AND s.device_id = p_device
        AND s.claimed_at IS NULL
      ORDER BY s.key_id
      FOR UPDATE SKIP LOCKED
      LIMIT 1
   )
  RETURNING k.key_id, k.public_key INTO v_prekey;

  RETURN QUERY
  SELECT d.device_id, d.registration_id, d.identity_key,
         sp.key_id, sp.public_key, sp.signature,
         v_prekey.key_id, v_prekey.public_key
    FROM public.e2ee_devices d
    JOIN public.e2ee_signed_prekeys sp
      ON sp.user_id = d.user_id AND sp.device_id = d.device_id
   WHERE d.user_id = p_user AND d.device_id = p_device
   ORDER BY sp.created_at DESC
   LIMIT 1;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.claim_prekey_bundle_for(uuid, integer) TO authenticated;

-- The reader asks. Returns true if a request is now open.
CREATE OR REPLACE FUNCTION public.e2ee_request_resend(p_message bigint, p_device integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_registered timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  SELECT d.created_at INTO v_registered FROM public.e2ee_devices d
   WHERE d.user_id = auth.uid() AND d.device_id = p_device;
  IF v_registered IS NULL THEN RETURN false; END IF;
  IF NOT public.e2ee_can_read_message(p_message) THEN RETURN false; END IF;
  -- New messages only: anything older than this phone's keys stays
  -- "Waiting for this message" (owner's call).
  IF NOT EXISTS (SELECT 1 FROM public.messages m
                  WHERE m.id = p_message
                    AND COALESCE(m.e2ee_version, 0) > 0
                    AND m.created_at >= v_registered - interval '2 minutes') THEN
    RETURN false;
  END IF;
  INSERT INTO public.e2ee_resend_requests (message_id, requester_user, requester_device)
  VALUES (p_message, auth.uid(), p_device)
  ON CONFLICT DO NOTHING;
  RETURN true;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_request_resend(bigint, integer) TO authenticated;

-- The sender collects open requests for messages they sent.
CREATE OR REPLACE FUNCTION public.e2ee_pending_resends()
RETURNS TABLE(message_id bigint, requester_user uuid, requester_device integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT r.message_id, r.requester_user, r.requester_device
    FROM public.e2ee_resend_requests r
    JOIN public.messages m ON m.id = r.message_id
   WHERE m.sender_id = auth.uid()
     AND r.fulfilled_at IS NULL
     AND r.created_at > now() - interval '30 days'
   ORDER BY r.created_at
   LIMIT 200;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_pending_resends() TO authenticated;

-- The sender answers with one device's copy.
CREATE OR REPLACE FUNCTION public.e2ee_fulfill_resend(
  p_message bigint, p_user uuid, p_device integer,
  p_sender_device integer, p_ciphertext text, p_type integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.messages m
                  WHERE m.id = p_message AND m.sender_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not your message.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.e2ee_resend_requests r
                  WHERE r.message_id = p_message AND r.requester_user = p_user
                    AND r.requester_device = p_device) THEN
    RAISE EXCEPTION 'Nobody asked for this copy.' USING ERRCODE = '42501';
  END IF;
  IF length(p_ciphertext) > 200000 THEN
    RAISE EXCEPTION 'Too large.' USING ERRCODE = '22001';
  END IF;
  INSERT INTO public.e2ee_message_copies (message_id, recipient_user,
    recipient_device, sender_device, ciphertext, ciphertext_type)
  VALUES (p_message, p_user, p_device, p_sender_device, p_ciphertext, p_type)
  ON CONFLICT (message_id, recipient_user, recipient_device) DO UPDATE
    SET sender_device = EXCLUDED.sender_device,
        ciphertext = EXCLUDED.ciphertext,
        ciphertext_type = EXCLUDED.ciphertext_type,
        created_at = now();
  UPDATE public.e2ee_resend_requests SET fulfilled_at = now()
   WHERE message_id = p_message AND requester_user = p_user
     AND requester_device = p_device;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_fulfill_resend(bigint, uuid, integer, integer, text, integer) TO authenticated;

-- The reader picks copies up.
CREATE OR REPLACE FUNCTION public.e2ee_copies_for(p_messages bigint[], p_device integer)
RETURNS TABLE(message_id bigint, sender_id uuid, sender_device integer,
              ciphertext text, ciphertext_type integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT c.message_id, m.sender_id, c.sender_device, c.ciphertext, c.ciphertext_type
    FROM public.e2ee_message_copies c
    JOIN public.messages m ON m.id = c.message_id
   WHERE c.recipient_user = auth.uid()
     AND c.recipient_device = p_device
     AND c.message_id = ANY (p_messages[1:200]);
$function$;
GRANT EXECUTE ON FUNCTION public.e2ee_copies_for(bigint[], integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Copies and requests are small and short-lived; prune after 30 days.
-- (Added to prune_operational_logs in a later patch if they grow.)
-- Check (read-only): expect 2 tables, 6 functions.
-- SELECT count(*) FROM pg_tables WHERE tablename IN ('e2ee_resend_requests','e2ee_message_copies');
-- SELECT count(*) FROM pg_proc WHERE proname IN ('e2ee_latest_device','claim_prekey_bundle_for',
--   'e2ee_request_resend','e2ee_pending_resends','e2ee_fulfill_resend','e2ee_copies_for');
