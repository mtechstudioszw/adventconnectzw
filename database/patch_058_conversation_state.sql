-- =====================================================================
--  PATCH 058 — Per-user conversation state (pin / mute / archive)
--
--  A private per-(user, conversation) row. Independent of the shared
--  conversations row so each participant pins/mutes/archives on their
--  own. Used by the chat list (pinned float to top, archived move to the
--  Archived tab, muted show a muted icon).
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.conversation_state (
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  conversation_id BIGINT NOT NULL
    REFERENCES public.conversations(id) ON DELETE CASCADE,
  pinned     BOOLEAN NOT NULL DEFAULT FALSE,
  muted      BOOLEAN NOT NULL DEFAULT FALSE,
  archived   BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, conversation_id)
);
CREATE INDEX IF NOT EXISTS conversation_state_user_idx
  ON public.conversation_state (user_id);

ALTER TABLE public.conversation_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversation_state_all ON public.conversation_state;
CREATE POLICY conversation_state_all ON public.conversation_state
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
