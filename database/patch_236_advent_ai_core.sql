-- =====================================================================
--  PATCH 236 — Advent AI, part 1: conversations + messages
--
--  The storage half of Advent AI.
--
--  ## Where this sits — CORRECTED 23 Aug 2026
--
--  These three files were originally numbered 233/234/235, which were
--  already taken by committed quiz patches. Renumbered to 236/237/238;
--  relative order unchanged. Every reference below names the new number.
--
--    patch_236  (this)  conversations + messages
--    patch_237         balance, ledger, entitlement
--    patch_238         config keys + service state
--    patch_239         monthly free refill + per-tier model
--
--  ## TWO PLANNED PARTS WERE NEVER WRITTEN
--
--  The original roadmap here promised five parts. Two of them do not
--  exist in any file, and the feature is NOT safe to ship without them:
--
--    * **The Bible corpus.** Nothing grounds the model's scripture
--      today, so every verse it produces is generated from memory —
--      exactly the fabrication the brief (§10) forbids. Until a real
--      corpus exists and the edge function quotes FROM it, Advent AI
--      must not present verse text as quoted scripture.
--
--    * **The app-knowledge base.** Without it the model answers "how do
--      I create a post?" from guesswork and will invent features this
--      app does not have (§32).
--
--  Both are retrieval tables plus a lookup function; neither needs
--  anything in these three files to change. They are the next patches.
--
--  ## The one rule this file exists to enforce
--
--  A conversation belongs to exactly one member and NOBODY else can ever
--  read it. Not a friend, not a church admin, not a super admin, not
--  staff. There is no admin read policy in this file and there must never
--  be one — people will type things here they have told no human being,
--  and every other "who can see this" question in the app has an answer
--  that is more permissive than this one. If a support case ever needs a
--  conversation, the member exports it from their own device.
--
--  `service_role` bypasses RLS, which is how the edge function writes the
--  assistant's reply. That is unavoidable (the function IS the thing
--  generating the reply) and is why the edge function never selects a row
--  it was not handed the id for.
--
--  ## Why user_id is on ai_messages as well as ai_conversations
--
--  Denormalised on purpose. The messages policy could join up to the
--  parent conversation, but that is a subquery per row on the hottest
--  read in the feature (paging a long conversation). The column is
--  written by a trigger from the parent, never by the client, so it
--  cannot drift and cannot be forged — see ai_messages_stamp_owner().
--
--  ## Deletion
--
--  Deleting a conversation deletes its messages (ON DELETE CASCADE) and
--  the member can do it themselves. The LEDGER is deliberately NOT
--  cascaded — see patch_237. Money records outlive the thing they were
--  spent on, or the balance stops reconciling.
--
--  IDEMPOTENT: yes.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Conversations
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_conversations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Null until the first exchange names it. The edge function derives a
  -- short title from the opening question; the member may rename it.
  title           TEXT,

  -- Rolling counters so the conversation list never has to COUNT(*) or
  -- read the last message body. Maintained by trigger.
  message_count   INTEGER NOT NULL DEFAULT 0,
  last_message_at TIMESTAMPTZ,

  -- A short excerpt of the most recent message, for the list row. Capped
  -- hard so the list query stays small even on a long conversation.
  last_preview    TEXT,

  archived        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT ai_conversations_title_len CHECK (
    title IS NULL OR char_length(title) <= 120
  ),
  CONSTRAINT ai_conversations_preview_len CHECK (
    last_preview IS NULL OR char_length(last_preview) <= 200
  )
);

-- The conversation list: newest activity first, for one member.
CREATE INDEX IF NOT EXISTS ai_conversations_user_recent_idx
  ON public.ai_conversations (user_id, last_message_at DESC NULLS LAST, created_at DESC);

-- ---------------------------------------------------------------------
--  Messages
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_messages (
  id              BIGSERIAL PRIMARY KEY,
  conversation_id UUID NOT NULL
                    REFERENCES public.ai_conversations(id) ON DELETE CASCADE,

  -- Denormalised owner. Stamped by trigger from the parent conversation,
  -- never accepted from the client. See the header note.
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  role            TEXT NOT NULL,
  content         TEXT NOT NULL DEFAULT '',

  -- Lifecycle of an ASSISTANT row. A user row is always 'complete'.
  --   streaming — the edge function is still writing into it
  --   complete  — finished normally
  --   failed    — provider/network/limit failure; `error_code` says which
  --   stopped   — the member cancelled mid-stream
  status          TEXT NOT NULL DEFAULT 'complete',

  -- A STABLE machine code ('provider_unavailable', 'rate_limited',
  -- 'insufficient_balance', ...). Never a raw provider message — the
  -- client maps this to its own copy so no upstream error text, stack
  -- trace or internal function name can reach a user's screen.
  error_code      TEXT,

  -- Accounting, written by the edge function from the provider's own
  -- usage report. Never from the client.
  model           TEXT,
  tokens_in       INTEGER NOT NULL DEFAULT 0,
  tokens_out      INTEGER NOT NULL DEFAULT 0,
  cost_micros     BIGINT  NOT NULL DEFAULT 0,

  -- Which tools ran, for debugging and for the "sources" strip under a
  -- grounded answer. Names + arguments only; never tool OUTPUT, which
  -- can be large and is already reflected in `content`.
  tool_calls      JSONB,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT ai_messages_role_chk
    CHECK (role IN ('user', 'assistant')),
  CONSTRAINT ai_messages_status_chk
    CHECK (status IN ('streaming', 'complete', 'failed', 'stopped')),
  -- Bounds the row, and bounds what one request can cost to re-read on
  -- every subsequent turn. The edge function rejects longer input before
  -- it ever gets here; this is the backstop.
  CONSTRAINT ai_messages_content_len CHECK (char_length(content) <= 32000),
  CONSTRAINT ai_messages_cost_nonneg CHECK (cost_micros >= 0)
);

-- Paging one conversation, oldest→newest. Also the (conversation_id, id)
-- keyset cursor the client pages on.
CREATE INDEX IF NOT EXISTS ai_messages_conversation_idx
  ON public.ai_messages (conversation_id, id);

-- ---------------------------------------------------------------------
--  Owner stamping
--
--  ai_messages.user_id is derived, not supplied. A client that inserts a
--  user turn sends only conversation_id + content; this fills the rest
--  from the parent row. Two things follow:
--    * a forged user_id is overwritten, not merely rejected;
--    * a message can never end up owned by someone who does not own the
--      conversation, which is what the SELECT policy relies on.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_messages_stamp_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_owner UUID;
BEGIN
  SELECT c.user_id INTO v_owner
    FROM public.ai_conversations c
   WHERE c.id = NEW.conversation_id;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'ai_messages: no such conversation';
  END IF;

  NEW.user_id := v_owner;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ai_messages_stamp_owner_trg ON public.ai_messages;
CREATE TRIGGER ai_messages_stamp_owner_trg
  BEFORE INSERT ON public.ai_messages
  FOR EACH ROW EXECUTE FUNCTION public.ai_messages_stamp_owner();

-- ---------------------------------------------------------------------
--  Conversation roll-up
--
--  Keeps message_count / last_message_at / last_preview current so the
--  list screen is one cheap indexed read.
--
--  Only COMPLETE assistant rows and user rows move the preview: a row
--  that is still streaming has partial text, and a failed row's text is
--  empty. Neither should become the list subtitle.
--
--  NOTE the COALESCE(NEW, OLD) — this trigger covers DELETE, and on a
--  DELETE `NEW` is NULL. Returning NULL from a BEFORE trigger silently
--  cancels the row (patch_189 is the scar). This one is AFTER, where the
--  return value is ignored, but the habit is the rule.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ai_conversations_rollup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_conv UUID := COALESCE(NEW.conversation_id, OLD.conversation_id);
BEGIN
  UPDATE public.ai_conversations c
     SET message_count = sub.n,
         last_message_at = sub.at,
         last_preview = sub.preview,
         updated_at = NOW()
    FROM (
      SELECT COUNT(*) AS n,
             MAX(m.created_at) AS at,
             LEFT(
               (SELECT m2.content
                  FROM public.ai_messages m2
                 WHERE m2.conversation_id = v_conv
                   AND m2.status = 'complete'
                   AND m2.content <> ''
                 ORDER BY m2.id DESC
                 LIMIT 1),
               200
             ) AS preview
        FROM public.ai_messages m
       WHERE m.conversation_id = v_conv
    ) sub
   WHERE c.id = v_conv;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS ai_conversations_rollup_trg ON public.ai_messages;
CREATE TRIGGER ai_conversations_rollup_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.ai_messages
  FOR EACH ROW EXECUTE FUNCTION public.ai_conversations_rollup();

-- `set_updated_at()` already exists in this database and is what every
-- other table uses. Reuse rather than add a second copy.
DROP TRIGGER IF EXISTS ai_conversations_touch_trg ON public.ai_conversations;
CREATE TRIGGER ai_conversations_touch_trg
  BEFORE UPDATE ON public.ai_conversations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------
--  RLS — owner only, no exceptions
-- ---------------------------------------------------------------------
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages      ENABLE ROW LEVEL SECURITY;

-- Force RLS even for the table owner, so a future SECURITY DEFINER
-- function written by someone in a hurry cannot read across members by
-- accident. service_role still bypasses (BYPASSRLS), which is the
-- documented, intentional hole the edge function uses.
ALTER TABLE public.ai_conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages      FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_conversations_own ON public.ai_conversations;
CREATE POLICY ai_conversations_own ON public.ai_conversations
  FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Members may INSERT their own user turns and READ everything in their
-- own conversations. They may NOT update or delete individual messages:
-- editing an assistant reply after the fact would let the transcript
-- disagree with what was billed, and there is no product reason for it.
-- Deleting the whole conversation is supported and cascades.
DROP POLICY IF EXISTS ai_messages_select_own ON public.ai_messages;
CREATE POLICY ai_messages_select_own ON public.ai_messages
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS ai_messages_insert_own ON public.ai_messages;
CREATE POLICY ai_messages_insert_own ON public.ai_messages
  FOR INSERT
  WITH CHECK (
    role = 'user'
    AND status = 'complete'
    AND EXISTS (
      SELECT 1 FROM public.ai_conversations c
       WHERE c.id = conversation_id
         AND c.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
--  Grants
--
--  Column-level on ai_messages, because `authenticated` must NOT be able
--  to write the accounting columns even though it can insert a row. RLS
--  governs WHICH rows; grants govern WHICH COLUMNS. A member who could
--  set cost_micros = 0 on their own turn would not break anything today
--  (the debit is computed server-side from the provider's usage report,
--  not read back from this table) — but the column would then be a
--  client-writable number that looks authoritative, which is how the
--  next person to touch this code gets it wrong.
--
--  There is no table-level grant to inherit from — same regime as
--  `profiles`. A column-level REVOKE is silently ignored while a
--  table-level grant exists, so the REVOKE ALL comes first.
-- ---------------------------------------------------------------------
REVOKE ALL ON public.ai_conversations FROM anon, authenticated;
REVOKE ALL ON public.ai_messages      FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ai_conversations TO authenticated;

GRANT SELECT ON public.ai_messages TO authenticated;
GRANT INSERT (conversation_id, role, content, status) ON public.ai_messages TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.ai_messages_id_seq TO authenticated;

-- anon gets nothing. Advent AI requires a signed-in member — there is no
-- logged-out mode and no shared demo conversation.

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- -- 1. No policy grants cross-member read:
-- SELECT tablename, policyname, cmd, qual
--   FROM pg_policies
--  WHERE schemaname='public' AND tablename LIKE 'ai_%'
--  ORDER BY tablename, cmd;
--   -- expect every USING clause to mention auth.uid()
--
-- -- 2. The accounting columns are not client-writable:
-- SELECT grantee, privilege_type, column_name
--   FROM information_schema.column_privileges
--  WHERE table_schema='public' AND table_name='ai_messages'
--    AND grantee='authenticated'
--  ORDER BY privilege_type, column_name;
--   -- expect INSERT on exactly: conversation_id, content, role, status
--
-- -- 3. Owner stamping cannot be forged (run as a member):
-- --    INSERT INTO ai_messages (conversation_id, role, content, user_id)
-- --    VALUES ('<someone elses conv>', 'user', 'hi', auth.uid());
-- --    -- expect: violates RLS (the WITH CHECK EXISTS fails first)
-- =====================================================================
