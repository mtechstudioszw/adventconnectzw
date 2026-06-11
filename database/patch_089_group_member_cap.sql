-- =====================================================================
--  PATCH 089 — cap user-created groups at 1024 members
--
--  A BEFORE INSERT trigger on conversation_members rejects a new member
--  once the group already has 1024 ACTIVE members (left_at IS NULL). This
--  covers every path (add members, create, join via invite). Church groups
--  use implicit membership (no rows) so they're unaffected — they remain
--  "everyone in the church".
-- =====================================================================

CREATE OR REPLACE FUNCTION public.enforce_group_member_cap()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (SELECT count(*) FROM public.conversation_members
        WHERE conversation_id = NEW.conversation_id
          AND left_at IS NULL) >= 1024 THEN
    RAISE EXCEPTION 'This group has reached the 1024-member limit.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_group_member_cap ON public.conversation_members;
CREATE TRIGGER trg_group_member_cap
  BEFORE INSERT ON public.conversation_members
  FOR EACH ROW EXECUTE FUNCTION public.enforce_group_member_cap();
