-- =====================================================================
--  PATCH 304 — inbox showed encrypted messages as base64
--  STATUS: APPLIED 3 Nov 2026 (by Claude via the Supabase connector)
--
--  Owner's screenshot: the inbox tile for an encrypted chat read
--  "MwjCkwMSIQVUJ1+Xpv1B44y7kUvOg0wW8jb…". my_inbox_previews() (patch_127)
--  returns messages.content but not e2ee_version, so the app's
--  E2eeEnvelope.isEncrypted(preview) check could never be true and the
--  ciphertext went straight onto the tile. (patch_294 fixed the shared
--  conversations.last_message column; this per-user preview overlays it.)
--
--  Now an encrypted row returns the 🔒 sentinel, which the app already
--  replaces with its locally decrypted preview or "New message". Same
--  signature, so no app update is needed and the ciphertext no longer
--  leaves the server for a preview at all.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.my_inbox_previews()
 RETURNS TABLE(conversation_id bigint, content text, message_type text, created_at timestamp with time zone, sent_at timestamp with time zone, sender_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (m.conversation_id)
         m.conversation_id,
         CASE WHEN COALESCE(m.e2ee_version, 0) > 0 THEN '🔒' ELSE m.content END,
         m.message_type,
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
