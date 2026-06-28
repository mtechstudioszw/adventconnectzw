-- patch_151_events_anon_share.sql
-- Let the public Open Graph share Worker (Cloudflare, anon key, no user
-- session) read APPROVED events for share cards.
--
-- Problem: events_select_all's USING clause inlined
--   EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.is_super_admin)
-- which the anon role cannot evaluate (no SELECT grant on profiles), so an
-- anonymous read of even an approved event failed with
--   42501 "permission denied for table profiles".
--
-- Fix: swap the inline subquery for the existing SECURITY DEFINER helper
-- public.is_super_admin(). It runs as its owner (which CAN read profiles),
-- so anon no longer touches profiles directly. Behaviour is identical:
--   * approved events  -> visible to everyone (incl. anon share Worker)
--   * own events       -> visible to the organizer
--   * all events       -> visible to super admins
alter policy events_select_all on public.events
  using (
    status = 'approved'
    or organizer_id = auth.uid()
    or public.is_super_admin()
  );

-- anon must be allowed to EXECUTE the helper for the policy to evaluate.
-- It is SECURITY DEFINER and simply returns false for an anonymous caller,
-- so granting execute exposes nothing.
grant execute on function public.is_super_admin() to anon;
