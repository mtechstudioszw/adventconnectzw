-- ---------------------------------------------------------------------
--  A payment receipt must survive Sabbath quiet hours.
--
--  suppress_sabbath_notifications() DROPS non-essential notifications
--  outright (RETURN NULL) while a user's Sabbath quiet window is open —
--  it doesn't defer them, it deletes them. Correct for a post like or a
--  devotion; wrong for a receipt.
--
--  Someone who subscribes on Sabbath has had money taken. The record of
--  that must not silently disappear, so 'payment_receipt' joins the
--  essential list. It is a financial record, not engagement.
--
--  Note this makes the receipt push through during quiet hours too. That
--  is the intended trade: a receipt is the one message a user is
--  entitled to receive at the moment they are charged.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_essential_notification(p_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT COALESCE(p_type, '') IN (
    'announcement_obituary',
    'announcement_urgent',
    'message',
    'friend_request',
    'friend_accepted',
    -- Money changed hands. Never drop this.
    'payment_receipt'
  );
$function$;
