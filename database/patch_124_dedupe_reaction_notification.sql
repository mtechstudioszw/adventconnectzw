-- =====================================================================
--  PATCH 124 — remove the DUPLICATE reaction-notification trigger
--
--  patch_117 added trg_notify_on_message_reaction (with a 60s de-dupe
--  window and type='reaction') intending to supersede patch_104's
--  trg_notify_message_reaction (no de-dupe, type='message'). But because
--  it used a different trigger + function name, BOTH triggers stayed live
--  on message_reactions — so every reaction fired TWO notifications, and
--  the un-deduped patch_104 one spammed on toggle/multi-emoji.
--
--  Bug report (#5): reacting shows "X reacted to your message" repeatedly
--  outside the chat. Fix: drop the older, un-deduped trigger + function so
--  only the patch_117 (deduped) path remains.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_notify_message_reaction ON public.message_reactions;
DROP FUNCTION IF EXISTS public.notify_message_reaction();
