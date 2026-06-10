-- =====================================================================
--  PATCH 066 — ensure_my_church_conversations()
--  No-arg convenience: looks up the caller's home church and lazily
--  creates its channel + members conversations. Called by the app on
--  chat-list load so the first church member to open chats materialises
--  the conversations everyone then sees (membership is implicit).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ensure_my_church_conversations()
RETURNS VOID AS $$
DECLARE v_church BIGINT;
BEGIN
  SELECT church_id INTO v_church FROM public.profiles WHERE id = auth.uid();
  IF v_church IS NULL THEN RETURN; END IF;
  PERFORM public.ensure_church_conversations(v_church);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.ensure_my_church_conversations() TO authenticated;
