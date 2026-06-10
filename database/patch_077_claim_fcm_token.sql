-- =====================================================================
--  PATCH 077 — one FCM token belongs to exactly one user
--
--  Symptom: "I get a push for my own message." The new-message trigger
--  never notifies the sender — but if the SAME device token is still
--  attached to another account's profile (multiple accounts on one
--  device, or a token left behind after sign-out), a message to that
--  account pushes to THIS device, so the sender sees it. RLS stops the
--  client from clearing another user's token, so this SECURITY DEFINER
--  RPC claims the token for the caller and removes it from everyone else.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.claim_fcm_token(p_token TEXT)
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL OR p_token IS NULL OR btrim(p_token) = '' THEN
    RETURN;
  END IF;
  -- Detach this token from any other account that still carries it.
  UPDATE public.profiles
     SET fcm_token = NULL
   WHERE fcm_token = p_token AND id <> auth.uid();
  -- Attach it to the current user.
  UPDATE public.profiles
     SET fcm_token = p_token
   WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.claim_fcm_token(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_fcm_token(TEXT) TO authenticated;
