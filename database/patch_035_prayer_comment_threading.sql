-- =====================================================================
--  PATCH 035 — Prayer comment threading + multi-message support
--
--  WHY: User spec (2026-05-31): "Put option to reply comment in
--       prayer requests, also the person who posted the prayer in
--       the comment should have a tag so people know who the owner
--       is and owner should also be able to reply in the comments."
--
--  CURRENT STATE: prayer_responses has a UNIQUE constraint on
--                 (prayer_id, user_id, response_type) — meaning a
--                 user can only post ONE message comment per prayer.
--                 That blocks both threading and a simple second
--                 reply from the same person, and would fail loudly
--                 if a user tried to send two pieces of encouragement.
--
--  WHAT:
--   1. Drop the broad UNIQUE constraint and replace it with a
--      partial unique index that only enforces uniqueness on the
--      'praying' response type (so the "did this user pray for
--      this prayer?" lookup still has a one-row guarantee). Message
--      comments are then free-form.
--   2. Add `parent_response_id` referencing prayer_responses(id) so
--      a reply can point at the message it replies to. NULL means
--      top-level. ON DELETE CASCADE so deleting a parent removes
--      its replies (matches post_comments threading from patch_017).
--   3. Index parent_response_id for the buildTree query.
--
--  IDEMPOTENT: yes — DROP IF EXISTS / ADD COLUMN IF NOT EXISTS /
--               CREATE INDEX IF NOT EXISTS.
-- =====================================================================


-- ----- 1. Free-form message comments --------------------------------
-- The old UNIQUE (prayer_id, user_id, response_type) constraint was
-- the wrong shape — it conflated praying-count uniqueness with
-- per-message uniqueness. Drop it and re-enforce only on 'praying'.
ALTER TABLE public.prayer_responses
  DROP CONSTRAINT IF EXISTS prayer_responses_unique_praying;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_prayer_responses_praying_only
  ON public.prayer_responses (prayer_id, user_id)
  WHERE response_type = 'praying';


-- ----- 2. Threading column ------------------------------------------
ALTER TABLE public.prayer_responses
  ADD COLUMN IF NOT EXISTS parent_response_id BIGINT
    REFERENCES public.prayer_responses(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_prayer_responses_parent
  ON public.prayer_responses (parent_response_id);

COMMENT ON COLUMN public.prayer_responses.parent_response_id IS
  'NULL for top-level message; otherwise references the comment '
  'this row is a reply to. Only applies to response_type = ''message''. '
  'The Flutter UI flattens any deeper nesting into a single reply list.';
