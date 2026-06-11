-- =====================================================================
--  PATCH 097 — "Delete for everyone" was blocked by the late-edit guard
--
--  messages_block_late_edits raised "edits only within 60 seconds"
--  whenever content changed. Soft-delete sets content='' so deleting any
--  message older than 60s failed ("could not delete"): the tombstone
--  never persisted, the recipient kept seeing the message, and replying
--  to it re-surfaced the old text. Exempt soft-deletes (is_deleted
--  toggled on) — only genuine content EDITS stay time-limited.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.messages_block_late_edits()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  -- A soft-delete (is_deleted flipping to true) is always allowed, even
  -- though it clears content. Read/delivered flips are unaffected.
  IF COALESCE(NEW.is_deleted, FALSE) AND NOT COALESCE(OLD.is_deleted, FALSE) THEN
    RETURN NEW;
  END IF;
  IF NEW.content IS DISTINCT FROM OLD.content THEN
    IF NOW() > OLD.created_at + INTERVAL '60 seconds' THEN
      RAISE EXCEPTION
        'Message edits are only allowed within 60 seconds of sending.';
    END IF;
    NEW.edited_at := NOW();
  END IF;
  RETURN NEW;
END;
$function$;
