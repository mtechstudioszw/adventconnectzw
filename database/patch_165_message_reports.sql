-- =====================================================================
--  PATCH 165 — Message-level reporting
--
--  Blocking a PERSON has existed since the messaging engine shipped.
--  Reporting a MESSAGE has not, and that is the gap that matters once a
--  community app is open to strangers: "block" is all-or-nothing and
--  leaves moderators with nothing to look at.
--
--  This deliberately EXTENDS the existing polymorphic `reports` table
--  rather than adding a parallel `message_reports` one. `reports`
--  already carries content_type / content_id / reason / details /
--  status / reviewed_by / action_taken, and the admin tooling already
--  reads it — a second table would mean a second moderation queue and a
--  second place to forget to look. Messages join it as
--  content_type = 'message', content_id = messages.id::text.
--
--  Two columns are new, and both earn their place:
--
--  * `reported_text` — the reporter's OWN copy of the message body,
--    frozen at report time. Redundant with messages.content today, but
--    (a) the sender can edit or delete-for-everyone afterwards, which
--    would otherwise erase the evidence, and (b) it is exactly the shape
--    end-to-end encryption needs, where the server cannot read the
--    message and the reporter's plaintext is the only thing a moderator
--    can ever see. Adding it now means E2EE doesn't reopen this table.
--
--  * `reported_user_id` — who SENT the reported content, so moderators
--    can group "everything reported about this account" without joining
--    back through a message that may since have been deleted.
--
--  Note messages.id and conversations.id are BIGINT in this schema, not
--  uuid; content_id is text, so the id is stored as text.
-- =====================================================================

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS reported_text    text,
  ADD COLUMN IF NOT EXISTS reported_user_id uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;

-- One report per person per message. A second tap should be a no-op, not
-- another row inflating the queue.
--
-- Scoped to messages ON PURPOSE. Live data already contains a duplicate
-- profile report, and retro-enforcing uniqueness across every content
-- type would either fail outright or require deleting somebody's filed
-- report. The rule applies where it is being introduced.
CREATE UNIQUE INDEX IF NOT EXISTS reports_message_once_idx
  ON public.reports (reported_by, content_id)
  WHERE content_type = 'message';

-- "Show me everything reported about this account."
CREATE INDEX IF NOT EXISTS reports_reported_user_idx
  ON public.reports (reported_user_id)
  WHERE reported_user_id IS NOT NULL;

-- The moderation queue reads pending reports newest-first.
CREATE INDEX IF NOT EXISTS reports_pending_idx
  ON public.reports (created_at DESC)
  WHERE status = 'pending';

-- =====================================================================
--  report_message() — file a report, stamping sender + text server-side
--
--  The client could pass reported_user_id itself, but then a malicious
--  client could attribute a report to the wrong account. Reading it from
--  the message row inside a SECURITY DEFINER function keeps that honest,
--  while still accepting the caller's own plaintext copy for the day the
--  server can no longer read message content.
--
--  Returns the report id. Reporting the same message twice updates the
--  existing report instead of failing, so the UI can be idempotent.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.report_message(
  p_message_id bigint,
  p_reason     text,
  p_details    text DEFAULT NULL,
  p_text_copy  text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_msg       record;
  v_report_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'a reason is required';
  END IF;

  SELECT id, sender_id, content
    INTO v_msg
    FROM public.messages
   WHERE id = p_message_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'message not found';
  END IF;

  -- Reporting your own message is always a mistake; refuse it rather
  -- than letting it sit in the queue.
  IF v_msg.sender_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot report your own message';
  END IF;

  INSERT INTO public.reports (
    reported_by, content_type, content_id, reason, details,
    status, reported_text, reported_user_id
  )
  VALUES (
    auth.uid(), 'message', v_msg.id::text, p_reason,
    NULLIF(btrim(p_details), ''), 'pending',
    COALESCE(NULLIF(btrim(p_text_copy), ''), v_msg.content),
    v_msg.sender_id
  )
  -- Matches the partial unique index above; the WHERE clause is what
  -- lets Postgres infer a partial index as the conflict target.
  ON CONFLICT (reported_by, content_id) WHERE content_type = 'message'
  DO UPDATE
    SET reason        = EXCLUDED.reason,
        details       = EXCLUDED.details,
        reported_text = EXCLUDED.reported_text
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.report_message(bigint, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.report_message(bigint, text, text, text) TO authenticated;
