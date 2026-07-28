-- =====================================================================
--  PATCH 172 — Church logo must reach the church's chat groups
--
--  TRACED 2026-07-28. The reported symptom was "the church photo doesn't
--  propagate". ChurchGroupAvatar was suspected and is INNOCENT: it takes
--  `photoUrl` and prefers it over the bundled SDA logo correctly.
--
--  The real cause is upstream of it. patch_065's
--  ensure_church_conversations() inserts the two auto conversations with
--  (is_group, name, church_id, church_kind, last_message_at) and NEVER
--  sets photo_url. Conversation.fromJson reads a group's avatar from
--  conversations.photo_url, so for every church group that value is NULL
--  — not stale, never written. The avatar could only ever be the default
--  logo, no matter what a church admin uploaded.
--
--  `name` has the same shape of bug, one step milder: it IS written, but
--  snapshotted as '<church> — Announcements' at creation, so renaming a
--  church leaves both groups carrying the old name forever.
--
--  FIX — three parts:
--    1. Backfill photo_url (and re-derive name) for existing rows.
--    2. A trigger on churches so future edits propagate immediately.
--    3. ensure_church_conversations() sets photo_url at creation, so a
--       church created after this patch is correct from the first row.
--
--  WHY IN THE DATABASE, not the client: photo_url is read by the inbox
--  list, the chat header and the cached copies of both. Fixing it at the
--  source means no screen needs to know a church group is special, and
--  the existing conversation cache heals on its next fetch.
--
--  RLS: none touched — no policy is created, altered or dropped.
--  IDEMPOTENT: yes.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1) Backfill. Every church group that exists today.
-- ---------------------------------------------------------------------
UPDATE public.conversations c
   SET photo_url = NULLIF(btrim(COALESCE(ch.profile_photo_url, '')), ''),
       name      = ch.name || CASE c.church_kind
                                WHEN 'channel' THEN ' — Announcements'
                                WHEN 'members' THEN ' — Members'
                                ELSE ''
                              END
  FROM public.churches ch
 WHERE c.church_id = ch.id
   AND c.church_kind IN ('channel','members')
   AND (
     c.photo_url IS DISTINCT FROM NULLIF(btrim(COALESCE(ch.profile_photo_url, '')), '')
     OR c.name IS DISTINCT FROM ch.name || CASE c.church_kind
                                             WHEN 'channel' THEN ' — Announcements'
                                             WHEN 'members' THEN ' — Members'
                                             ELSE ''
                                           END
   );


-- ---------------------------------------------------------------------
--  2) Keep them in sync from here on.
--
--  Fires only when the two columns we mirror actually change, so ordinary
--  church edits (address, pastor, phone) don't touch conversations.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_church_conversation_identity()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.profile_photo_url IS DISTINCT FROM OLD.profile_photo_url
     OR NEW.name IS DISTINCT FROM OLD.name THEN
    UPDATE public.conversations c
       SET photo_url = NULLIF(btrim(COALESCE(NEW.profile_photo_url, '')), ''),
           name      = NEW.name || CASE c.church_kind
                                     WHEN 'channel' THEN ' — Announcements'
                                     WHEN 'members' THEN ' — Members'
                                     ELSE ''
                                   END
     WHERE c.church_id = NEW.id
       AND c.church_kind IN ('channel','members');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_church_conversation_identity ON public.churches;
CREATE TRIGGER trg_sync_church_conversation_identity
  AFTER UPDATE OF profile_photo_url, name ON public.churches
  FOR EACH ROW EXECUTE FUNCTION public.sync_church_conversation_identity();


-- ---------------------------------------------------------------------
--  3) Set it at creation time too, so a brand-new church is never
--     briefly wrong. Otherwise identical to patch_065's version.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_church_conversations(p_church_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_name  TEXT;
  v_photo TEXT;
BEGIN
  SELECT name, NULLIF(btrim(COALESCE(profile_photo_url, '')), '')
    INTO v_name, v_photo
    FROM public.churches WHERE id = p_church_id;
  IF v_name IS NULL THEN RETURN; END IF;

  INSERT INTO public.conversations
    (is_group, name, photo_url, church_id, church_kind, last_message_at)
  SELECT TRUE, v_name || ' — Announcements', v_photo, p_church_id, 'channel', now()
  WHERE NOT EXISTS (SELECT 1 FROM public.conversations
                     WHERE church_id = p_church_id AND church_kind = 'channel');

  INSERT INTO public.conversations
    (is_group, name, photo_url, church_id, church_kind, last_message_at)
  SELECT TRUE, v_name || ' — Members', v_photo, p_church_id, 'members', now()
  WHERE NOT EXISTS (SELECT 1 FROM public.conversations
                     WHERE church_id = p_church_id AND church_kind = 'members');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.ensure_church_conversations(BIGINT) TO authenticated;


-- =====================================================================
--  VERIFY
--    SELECT c.id, c.church_kind, c.name, c.photo_url, ch.profile_photo_url
--      FROM conversations c JOIN churches ch ON ch.id = c.church_id
--     WHERE c.church_kind IS NOT NULL
--       AND c.photo_url IS DISTINCT FROM
--           NULLIF(btrim(COALESCE(ch.profile_photo_url,'')),'');
--  Zero rows = every church group is showing its own logo.
-- =====================================================================
