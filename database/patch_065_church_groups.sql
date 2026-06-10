-- =====================================================================
--  PATCH 065 — Church groups (foundation)
--
--  Each church gets TWO auto conversations (hybrid model):
--    - church_kind='channel'  → announcements; only verified church
--                               admins (church_admins.status='approved')
--                               + super admin can post; all church
--                               members read.
--    - church_kind='members'  → open chat; any member of the church can
--                               post.
--  Membership is IMPLICIT: a user "is in" a church conversation when
--  profiles.church_id = conversations.church_id. No materialised member
--  rows (scales to huge congregations, no fan-out). Conversations are
--  is_group=TRUE so the existing group-aware chat UI applies; they are
--  pinned + non-leavable in the app.
-- =====================================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS church_id   BIGINT REFERENCES public.churches(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS church_kind TEXT;   -- 'channel' | 'members'

CREATE UNIQUE INDEX IF NOT EXISTS conversations_church_kind_uidx
  ON public.conversations (church_id, church_kind)
  WHERE church_id IS NOT NULL;

-- ----- Helpers --------------------------------------------------------
-- The caller belongs to the church that owns conversation p_conv.
CREATE OR REPLACE FUNCTION public.is_my_church_conv(p_conv BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversations c
      JOIN public.profiles p ON p.id = auth.uid()
     WHERE c.id = p_conv
       AND c.church_id IS NOT NULL
       AND c.church_id = p.church_id
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.is_my_church_conv(BIGINT) TO authenticated;

-- The caller is a verified admin of the church that owns p_conv.
CREATE OR REPLACE FUNCTION public.is_my_church_admin_conv(p_conv BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversations c
      JOIN public.church_admins ca ON ca.church_id = c.church_id
     WHERE c.id = p_conv
       AND ca.user_id = auth.uid()
       AND ca.status = 'approved'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.is_my_church_admin_conv(BIGINT) TO authenticated;

-- ----- RLS: church members can see church conversations --------------
DROP POLICY IF EXISTS conversations_select_church ON public.conversations;
CREATE POLICY conversations_select_church ON public.conversations
  FOR SELECT TO authenticated
  USING (church_id IS NOT NULL AND public.is_my_church_conv(id));

-- ----- RLS: read church messages -------------------------------------
DROP POLICY IF EXISTS messages_select_church ON public.messages;
CREATE POLICY messages_select_church ON public.messages
  FOR SELECT TO authenticated
  USING (public.is_my_church_conv(conversation_id));

-- ----- RLS: post to members chat (any church member) -----------------
DROP POLICY IF EXISTS messages_insert_church_members ON public.messages;
CREATE POLICY messages_insert_church_members ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND public.user_is_active()
    AND public.is_my_church_conv(conversation_id)
    AND EXISTS (SELECT 1 FROM public.conversations c
                 WHERE c.id = conversation_id AND c.church_kind = 'members')
  );

-- ----- RLS: post to channel (verified church admin / super admin) ----
DROP POLICY IF EXISTS messages_insert_church_channel ON public.messages;
CREATE POLICY messages_insert_church_channel ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND public.user_is_active()
    AND EXISTS (SELECT 1 FROM public.conversations c
                 WHERE c.id = conversation_id AND c.church_kind = 'channel')
    AND (
      public.is_my_church_admin_conv(conversation_id)
      OR EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.id = auth.uid() AND COALESCE(p.is_super_admin, FALSE))
    )
  );

-- ----- Lazily create the caller's church conversations ---------------
-- Called by the app after the home church is known. Idempotent.
CREATE OR REPLACE FUNCTION public.ensure_church_conversations(p_church_id BIGINT)
RETURNS VOID AS $$
DECLARE v_name TEXT;
BEGIN
  IF p_church_id IS NULL THEN RETURN; END IF;
  SELECT name INTO v_name FROM public.churches WHERE id = p_church_id;
  IF v_name IS NULL THEN RETURN; END IF;

  INSERT INTO public.conversations
    (is_group, name, church_id, church_kind, last_message_at)
  SELECT TRUE, v_name || ' — Announcements', p_church_id, 'channel', now()
  WHERE NOT EXISTS (SELECT 1 FROM public.conversations
                     WHERE church_id = p_church_id AND church_kind = 'channel');

  INSERT INTO public.conversations
    (is_group, name, church_id, church_kind, last_message_at)
  SELECT TRUE, v_name || ' — Members', p_church_id, 'members', now()
  WHERE NOT EXISTS (SELECT 1 FROM public.conversations
                     WHERE church_id = p_church_id AND church_kind = 'members');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.ensure_church_conversations(BIGINT) TO authenticated;
