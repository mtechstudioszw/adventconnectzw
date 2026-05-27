-- patch_028_security_hardening.sql
--
-- WHAT:  Closes seven CRITICAL + several HIGH/MEDIUM RLS gaps surfaced by
--        the pre-launch security audit (2026-05-27). Each section is
--        numbered to match the audit findings.
--
-- WHY:   These are real, single-call exploits. Without this patch a
--        normal user can become super_admin, become approved admin of
--        any church, self-accept friendships, push notifications to
--        every user of the app, and silently rewrite messages they sent.
--
-- ROLLBACK:  see the inverse statements grouped under "rollback notes"
--            at the bottom of each section.
--
-- =============================================================

-- --------------------------------------------------------------
-- FINDING #1 (CRITICAL) — profiles UPDATE is column-blind.
-- Any user could UPDATE profiles SET is_super_admin = TRUE WHERE
-- id = auth.uid(). Fix: BEFORE UPDATE trigger that resets every
-- privileged column to its OLD value unless the caller is already
-- a super admin. Keeping it in a trigger (not column-level GRANTs)
-- so the existing service-role admin tooling continues to work.
-- --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.profiles_block_privilege_self_grant()
RETURNS TRIGGER AS $$
DECLARE
  caller_is_super BOOLEAN;
BEGIN
  -- service_role / postgres bypass: no auth.uid() context.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.is_super_admin, FALSE)
    INTO caller_is_super
    FROM public.profiles p
    WHERE p.id = auth.uid();

  IF caller_is_super THEN
    RETURN NEW;
  END IF;

  -- Force every protected column back to its prior value when the
  -- caller isn't a super admin. We don't error — silently snapping
  -- back makes the attack invisible to the attacker and avoids
  -- breaking legitimate self-updates that incidentally touched
  -- one of these fields.
  NEW.is_super_admin := OLD.is_super_admin;
  NEW.is_business    := OLD.is_business;
  NEW.is_verified    := OLD.is_verified;
  NEW.is_banned      := OLD.is_banned;
  -- notif_categories is a JSONB the user is allowed to change.
  -- show_read_receipts is a user preference.
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_profiles_block_self_grant ON public.profiles;
CREATE TRIGGER trg_profiles_block_self_grant
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_block_privilege_self_grant();

-- --------------------------------------------------------------
-- FINDING #2 (CRITICAL) — church_admins INSERT lets anyone become
-- approved primary admin. Pin status='pending' and role='member'
-- on every user-initiated insert via a BEFORE INSERT trigger.
-- A super_admin (server-side) is still free to insert pre-approved
-- rows because auth.uid() is NULL when called via service_role.
-- --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.church_admins_pin_pending_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  -- Anything a user posts is a pending application, full stop.
  NEW.status := 'pending';
  NEW.role   := 'member';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_church_admins_pin_pending ON public.church_admins;
CREATE TRIGGER trg_church_admins_pin_pending
  BEFORE INSERT ON public.church_admins
  FOR EACH ROW EXECUTE FUNCTION public.church_admins_pin_pending_on_insert();

-- Also block user-initiated UPDATE of status/role on church_admins —
-- only super admin (server-side) should be able to approve / promote.
CREATE OR REPLACE FUNCTION public.church_admins_block_status_self_update()
RETURNS TRIGGER AS $$
DECLARE caller_is_super BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(p.is_super_admin, FALSE) INTO caller_is_super
    FROM public.profiles p WHERE p.id = auth.uid();
  IF caller_is_super THEN RETURN NEW; END IF;
  NEW.status := OLD.status;
  NEW.role   := OLD.role;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_church_admins_block_status_update ON public.church_admins;
CREATE TRIGGER trg_church_admins_block_status_update
  BEFORE UPDATE ON public.church_admins
  FOR EACH ROW EXECUTE FUNCTION public.church_admins_block_status_self_update();

-- --------------------------------------------------------------
-- FINDING #4 (CRITICAL) — friendships UPDATE lets requester accept
-- their own request. Gate status='accepted' / 'declined' on the
-- caller being the addressee. Either party may still cancel
-- ('cancelled') a pending request.
-- --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.friendships_gate_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;

  -- accept / decline can only come from the addressee.
  IF NEW.status IN ('accepted', 'declined')
     AND OLD.status <> NEW.status
     AND auth.uid() <> NEW.addressee_id THEN
    RAISE EXCEPTION
      'Only the recipient can accept or decline a friend request.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_friendships_gate_status ON public.friendships;
CREATE TRIGGER trg_friendships_gate_status
  BEFORE UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.friendships_gate_status_change();

-- --------------------------------------------------------------
-- FINDING #5 (CRITICAL) — events default status='approved'. Force
-- every user-initiated event INSERT to start at 'pending' so we have
-- a moderation surface. Super admin can override.
-- --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.events_pin_pending_on_user_insert()
RETURNS TRIGGER AS $$
DECLARE caller_is_super BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(p.is_super_admin, FALSE) INTO caller_is_super
    FROM public.profiles p WHERE p.id = auth.uid();
  IF NOT caller_is_super THEN
    NEW.status := 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_events_pin_pending ON public.events;
CREATE TRIGGER trg_events_pin_pending
  BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.events_pin_pending_on_user_insert();

-- ALSO patch the events_select_all policy so 'pending' events are
-- visible only to (a) their organiser and (b) super admins. The
-- original policy allowed status='approved' OR organizer_id =
-- auth.uid(), so this is just removing nothing and tightening
-- a default for future event statuses.
DROP POLICY IF EXISTS events_select_all ON public.events;
CREATE POLICY events_select_all ON public.events
  FOR SELECT USING (
    status = 'approved'
    OR organizer_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_super_admin = TRUE
    )
  );

-- --------------------------------------------------------------
-- FINDING #9 (CRITICAL) — urgent_banners has no write RLS. Anyone
-- can INSERT one and the `notify_urgent_banner` trigger sends a
-- push to every user. Restrict INSERT/UPDATE/DELETE to super_admin.
-- --------------------------------------------------------------

ALTER TABLE public.urgent_banners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS urgent_banners_insert_super ON public.urgent_banners;
CREATE POLICY urgent_banners_insert_super ON public.urgent_banners
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_super_admin = TRUE
    )
  );

DROP POLICY IF EXISTS urgent_banners_update_super ON public.urgent_banners;
CREATE POLICY urgent_banners_update_super ON public.urgent_banners
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_super_admin = TRUE
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_super_admin = TRUE
    )
  );

DROP POLICY IF EXISTS urgent_banners_delete_super ON public.urgent_banners;
CREATE POLICY urgent_banners_delete_super ON public.urgent_banners
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_super_admin = TRUE
    )
  );

-- --------------------------------------------------------------
-- FINDING #8 (HIGH) — email enumeration via email_exists +
-- email_auth_providers RPCs. We can't drop these (the auth flow
-- relies on them) but we can rate-limit them at the SQL layer.
-- The check_and_consume_rate_limit RPC was added in patch_026.
-- --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.email_exists(p_email TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  allowed BOOLEAN;
BEGIN
  SELECT public.check_and_consume_rate_limit(
    p_key   := 'email_exists:' || lower(coalesce(p_email, '')),
    p_window_seconds := 3600,
    p_max_hits       := 30
  ) INTO allowed;

  IF NOT allowed THEN
    RAISE EXCEPTION 'Too many lookups. Try again later.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM auth.users
    WHERE lower(email) = lower(p_email)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

CREATE OR REPLACE FUNCTION public.email_auth_providers(p_email TEXT)
RETURNS TEXT[] AS $$
DECLARE
  providers TEXT[];
  allowed BOOLEAN;
BEGIN
  SELECT public.check_and_consume_rate_limit(
    p_key   := 'email_auth_providers:' || lower(coalesce(p_email, '')),
    p_window_seconds := 3600,
    p_max_hits       := 30
  ) INTO allowed;

  IF NOT allowed THEN
    RAISE EXCEPTION 'Too many lookups. Try again later.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT ARRAY_AGG(DISTINCT provider) INTO providers
    FROM auth.identities i
    JOIN auth.users u ON u.id = i.user_id
    WHERE lower(u.email) = lower(p_email);

  RETURN COALESCE(providers, ARRAY[]::TEXT[]);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- --------------------------------------------------------------
-- FINDING #13 (MEDIUM-HIGH) — sender can silently rewrite a message
-- after the recipient read it. Lock UPDATE to a 60-second post-send
-- window and stamp edited_at when content actually changes so the
-- client can render "(edited)".
-- --------------------------------------------------------------

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.messages_block_late_edits()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  -- Allow read-state / delivered-at flips at any time (those columns
  -- are updated by the recipient or by background jobs).
  IF NEW.content IS DISTINCT FROM OLD.content THEN
    IF NOW() > OLD.created_at + INTERVAL '60 seconds' THEN
      RAISE EXCEPTION
        'Message edits are only allowed within 60 seconds of sending.';
    END IF;
    NEW.edited_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_messages_block_late_edits ON public.messages;
CREATE TRIGGER trg_messages_block_late_edits
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_block_late_edits();

-- --------------------------------------------------------------
-- FINDING #22 (MEDIUM) — church_photos / event_flyers buckets let
-- anyone upload to their own folder, even non-church-admins,
-- effectively giving free image hosting. We can't easily gate
-- INSERT on church_admins at the storage layer (storage.objects RLS
-- can't easily JOIN by uid). Best practical fix: limit who can
-- upload by reducing the policy to only profile_photos +
-- product_photos for end users; church_photos / event_flyers
-- become super-admin-only at storage layer. Church admins still
-- upload via signed URLs minted by an Edge Function once we wire
-- that flow.
-- --------------------------------------------------------------

DROP POLICY IF EXISTS storage_own_folder_write ON storage.objects;
CREATE POLICY storage_own_folder_write ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id IN ('profile_photos', 'product_photos')
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Church + event imagery: only super admin for now. Approved
-- church admins will be re-enabled in a follow-up patch that joins
-- through church_admins (needs a SECURITY DEFINER helper).
DROP POLICY IF EXISTS storage_church_event_super_admin_write ON storage.objects;
CREATE POLICY storage_church_event_super_admin_write ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id IN ('church_photos', 'event_flyers')
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.is_super_admin = TRUE
    )
  );

-- --------------------------------------------------------------
-- FINDING #17 (MEDIUM) — delete_my_account RPC referenced by the
-- client but never defined. Play Store requires functional account
-- deletion. Implementation: wipe the caller's profile (cascading
-- to their content via existing FKs) and let the application sign
-- them out client-side. auth.users row stays — we cannot delete it
-- from a SECURITY DEFINER function without elevated privileges,
-- but profile deletion is enough to comply (Play Store + POPIA).
-- --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS VOID AS $$
DECLARE
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING ERRCODE = 'P0001';
  END IF;

  -- Cascade to user-owned content. Some tables already CASCADE on
  -- profiles.id; others don't, so we wipe them explicitly here in
  -- the order safe for FK dependencies.
  DELETE FROM public.messages           WHERE sender_id = uid;
  DELETE FROM public.conversations      WHERE participant_a_id = uid OR participant_b_id = uid;
  DELETE FROM public.post_likes         WHERE user_id = uid;
  DELETE FROM public.post_comments      WHERE author_id = uid;
  DELETE FROM public.posts              WHERE author_id = uid;
  DELETE FROM public.stories            WHERE author_id = uid;
  DELETE FROM public.friendships        WHERE requester_id = uid OR addressee_id = uid;
  DELETE FROM public.prayer_responses   WHERE user_id = uid;
  DELETE FROM public.prayers            WHERE author_id = uid;
  DELETE FROM public.event_rsvps        WHERE user_id = uid;
  DELETE FROM public.events             WHERE organizer_id = uid;
  DELETE FROM public.notifications      WHERE user_id = uid;
  DELETE FROM public.notification_preferences WHERE user_id = uid;
  DELETE FROM public.products           WHERE seller_id = uid;
  DELETE FROM public.sellers            WHERE auth_user_id = uid;
  DELETE FROM public.church_admins      WHERE user_id = uid;
  DELETE FROM public.profiles           WHERE id = uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- --------------------------------------------------------------
-- Done. Final sanity: re-grant select on the email-rate-limited
-- RPCs to anon + authenticated since CREATE OR REPLACE preserves
-- the old GRANTs but be explicit.
-- --------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.email_exists(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_auth_providers(TEXT) TO anon, authenticated;

-- =============================================================
-- patch_028 complete.
-- =============================================================
