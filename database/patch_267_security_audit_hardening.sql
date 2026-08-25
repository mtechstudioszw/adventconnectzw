-- =====================================================================
--  patch_267 — security audit hardening (25 Aug 2026)
--
--  Three fixes from the pre-release audit. All server-side; none needs
--  a client change.
--
--    1. messages     — freeze identity + timing columns on UPDATE
--    2. profiles     — revoke anon's grants; freeze account_type
--    3. conversations— rate-limit thread creation
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. messages — a sender could relocate their own message
--
--  `messages_update_sender` checks only `auth.uid() = sender_id`, in
--  both USING and WITH CHECK. It never re-validates conversation_id,
--  and `authenticated` holds an UPDATE grant on that column. So a
--  member could send themselves a message and then repoint it at any
--  conversation whose id they knew — it renders in that thread for its
--  real participants. `messages_block_late_edits` only guards
--  `content`, so the 60-second window did not apply here.
--
--  The same gap left created_at / sent_at writable (fabricated chat
--  history) and left the receipt columns writable BY THE SENDER — a
--  sender could mark their own message read by the recipient.
--
--  Fixed in a trigger rather than in the policy: a WITH CHECK cannot
--  express "unchanged", and widening it would still miss the receipts.
--
--  Receipts stay writable by the RECIPIENT. All four receipt paths —
--  mark_conversation_read, mark_conversation_delivered,
--  mark_message_delivered, mark_all_incoming_delivered — are SECURITY
--  DEFINER but keep the CALLER's auth.uid(), which is the recipient,
--  not the sender. Conditioning the freeze on "caller is the sender"
--  therefore lets those four through untouched.
--
--  The client's own two direct UPDATEs (MessagingService.softDeleteMessage
--  and .editMessage) touch only is_deleted / content / media_url /
--  edited_at, none of which this trigger holds.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.messages_freeze_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- No JWT = service role / DB-internal. Backfills and edge functions
  -- are the only callers that may legitimately move a message.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Never movable, never re-datable, by anyone holding a JWT.
  NEW.conversation_id := OLD.conversation_id;
  NEW.sender_id       := OLD.sender_id;
  NEW.created_at      := OLD.created_at;
  NEW.sent_at         := OLD.sent_at;

  -- A sender may not write their own receipts.
  IF auth.uid() = OLD.sender_id THEN
    NEW.read            := OLD.read;
    NEW.read_at         := OLD.read_at;
    NEW.delivered_at    := OLD.delivered_at;
    NEW.voice_played_at := OLD.voice_played_at;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_messages_freeze_identity ON public.messages;

-- BEFORE UPDATE triggers fire in alphabetical order, so
-- trg_messages_block_late_edits runs first. That is the order we want:
-- it compares NEW.content to OLD.content and reads OLD.created_at, and
-- this trigger touches neither. Backdating is still blocked, because
-- created_at is restored here before the row is written.
CREATE TRIGGER trg_messages_freeze_identity
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_freeze_identity();


-- ---------------------------------------------------------------------
--  2a. profiles — anon held grants it can never use
--
--  anon had table-level INSERT/DELETE/REFERENCES/TRIGGER on profiles,
--  which in turn surfaced as column privileges on is_super_admin,
--  is_verified and is_banned. Not reachable — every profiles policy
--  requires auth.uid(), which is NULL for anon — but removed anyway.
--
--  Per the CLAUDE.md rule: a column-level REVOKE is silently ignored
--  while a table-level grant stands, so the TABLE grant is what has to
--  go. Signup is unaffected — the profile row is created by patch_001's
--  SECURITY DEFINER trigger on auth.users, never by the anon client.
--
--  is_verified_admin is re-granted: patch_151's anon share cards read it.
-- ---------------------------------------------------------------------
REVOKE ALL ON public.profiles FROM anon;
GRANT SELECT (is_verified_admin) ON public.profiles TO anon;


-- ---------------------------------------------------------------------
--  2b. profiles — account_type was not frozen
--
--  account_type's CHECK constraint allows 'super_admin', and the
--  privilege trigger never snapped it back. Authorization reads the
--  is_super_admin BOOLEAN everywhere, so this granted nothing at the
--  database level — but it is a privilege-shaped column that the client
--  reads, so it is derived from the seller / church-admin flows and
--  must never be self-assigned.
--
--  Rewritten whole rather than patched, so the body stays readable as
--  one piece. Everything else is identical to patch_188's version.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  -- No JWT = the service role (edge functions) or a DB-internal caller.
  -- That is the only path allowed to grant premium.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Premium is BOUGHT, never self-assigned, so it covers super admins
  -- too — this is the one privilege they may not hand themselves.
  NEW.premium_until := OLD.premium_until;

  SELECT COALESCE(p.is_super_admin, FALSE)
    INTO caller_is_super
    FROM public.profiles p
    WHERE p.id = auth.uid();

  IF caller_is_super THEN
    RETURN NEW;
  END IF;

  NEW.is_super_admin := OLD.is_super_admin;
  NEW.is_verified    := OLD.is_verified;
  NEW.is_banned      := OLD.is_banned;

  -- NEW (patch 267): see 2b above.
  NEW.account_type   := OLD.account_type;

  -- `is_business` can move TRUE during the auto-approve RPC; otherwise
  -- snap it back to whatever it was before.
  IF current_setting('app.auto_approving_business', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_business := OLD.is_business;
  END IF;

  -- patch 188: the gold tick is DERIVED, never self-assigned.
  -- recompute_verified_admin() raises this flag for the duration of its
  -- own transaction; every other caller gets snapped back. The flag is
  -- transaction-local (set_config's third argument), so it cannot leak
  -- into another statement or another session.
  IF current_setting('app.recomputing_verified_admin', true)
       IS DISTINCT FROM 'true' THEN
    NEW.is_verified_admin := OLD.is_verified_admin;
  END IF;

  RETURN NEW;
END;
$fn$;


-- ---------------------------------------------------------------------
--  3. conversations — unlimited thread creation
--
--  messages, posts, comments, friendships, reports and stories all
--  carry an enforce_write_rate_limit trigger. conversations did not, so
--  a script could open threads without bound. 60/hour is far above real
--  use (the app opens one per person you talk to) and well under what
--  makes spam worthwhile.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_rate_limit_conversations ON public.conversations;
CREATE TRIGGER trg_rate_limit_conversations
  BEFORE INSERT ON public.conversations
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_write_rate_limit(
    'conversation_create', '60', '3600');
