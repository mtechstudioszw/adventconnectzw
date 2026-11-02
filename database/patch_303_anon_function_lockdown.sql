-- =====================================================================
--  PATCH 303 — five functions no longer callable without signing in
--  STATUS: APPLIED 2 Nov 2026 (by Claude via the Supabase connector,
--  verified: anon=false on all five; authenticated keeps the three the
--  app calls; the two SECURITY DEFINER callers of the server-only ones,
--  trg_church_admin_verify and profiles_block_privilege_self_grant, run
--  as the owner and are unaffected).
--
--  Found by the security advisor + a scan for SECURITY DEFINER functions
--  that write data, are executable by anon, and never look at auth.uid():
--
--   claim_prekey_bundle_for — anyone, signed out, could burn through any
--     member's one-time encryption prekeys. Messages still send (the
--     signed prekey is the fallback), but with weaker forward secrecy.
--   quiz_match_progress / quiz_matches_sweep — game housekeeping.
--   recompute_verified_admin / prune_stale_live_notifications —
--     server-only (triggers and cron), now closed to the app too.
--
--  Left alone on purpose: check_and_consume_rate_limit and
--  register_otp_resend are used before sign-in (password reset, OTP).
--
--  CLAUDE.md checklist: no profiles column; no triggers.
-- =====================================================================

BEGIN;
REVOKE EXECUTE ON FUNCTION public.claim_prekey_bundle_for(uuid, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.claim_prekey_bundle_for(uuid, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.quiz_match_progress(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.quiz_match_progress(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.quiz_matches_sweep() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.quiz_matches_sweep() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.recompute_verified_admin(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prune_stale_live_notifications() FROM PUBLIC, anon, authenticated;
COMMIT;
