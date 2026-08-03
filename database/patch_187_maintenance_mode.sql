-- patch_187 (#22): maintenance mode, enforced server-side.
--
-- The founder's requirement was specific: when it is on, **no user can use
-- the app and it cannot be bypassed**. A client-side check alone cannot
-- honour that — a flag read at launch is defeated by staying in the app, by
-- an old build, or by a network failure that makes the check fail open (and
-- failing open is exactly what `ForceUpdateService.check()` deliberately
-- does). So the teeth are in the database, where a modified client cannot
-- reach them — see "The teeth" at the bottom of this file.
--
-- Reuses the existing `app_config` table that `ForceUpdateService` reads,
-- rather than inventing a second remote-config mechanism.
--
-- WHAT IS BLOCKED: every content write — posts, comments, messages,
-- prayers, products, events, news, announcements, reactions. Reads are
-- deliberately left alone, for two reasons: the app must still be able to
-- fetch the maintenance notice itself, and adding a maintenance clause to
-- the read policy of forty tables is a far bigger blast radius than the
-- feature is worth. The client hard-gates the UI on top of this, the same
-- way `/update-required` already does.
--
-- SUPER ADMINS ARE EXEMPT, on purpose: somebody has to be able to fix
-- whatever the maintenance is for, and to turn it back off.

-- ---- Config + predicate -----------------------------------------------------

INSERT INTO public.app_config (key, value)
VALUES ('maintenance_mode', '0')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.app_config (key, value)
VALUES ('maintenance_message',
        'Advent Connect is down for scheduled maintenance. We will be back shortly.')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.app_config (key, value)
VALUES ('maintenance_ends_at', '')
ON CONFLICT (key) DO NOTHING;

-- STABLE, not VOLATILE: it is consulted once per statement rather than once
-- per row, which matters when it sits inside an RLS policy.
CREATE OR REPLACE FUNCTION public.maintenance_active()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
           (SELECT c.value = '1' FROM public.app_config c
             WHERE c.key = 'maintenance_mode'),
           false
         )
         -- Whoever has to fix it must still be able to work.
         AND NOT public.is_super_admin();
$$;

GRANT EXECUTE ON FUNCTION public.maintenance_active() TO authenticated, anon;

-- What the client shows on the blocking screen. Readable by everyone,
-- including during maintenance — this is the one thing that must get out.
CREATE OR REPLACE FUNCTION public.maintenance_status()
RETURNS TABLE (active boolean, message text, ends_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE((SELECT c.value = '1' FROM public.app_config c
               WHERE c.key = 'maintenance_mode'), false),
    COALESCE((SELECT NULLIF(btrim(c.value), '') FROM public.app_config c
               WHERE c.key = 'maintenance_message'),
             'Advent Connect is down for maintenance.'),
    (SELECT NULLIF(btrim(c.value), '')::timestamptz FROM public.app_config c
      WHERE c.key = 'maintenance_ends_at');
$$;

GRANT EXECUTE ON FUNCTION public.maintenance_status() TO authenticated, anon;

-- ---- The switch -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_set_maintenance(
  p_on      boolean,
  p_message text DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_was boolean;
  v_msg text;
BEGIN
  PERFORM public.assert_staff('owner');

  SELECT COALESCE(value = '1', false) INTO v_was
    FROM public.app_config WHERE key = 'maintenance_mode';

  UPDATE public.app_config SET value = CASE WHEN p_on THEN '1' ELSE '0' END
   WHERE key = 'maintenance_mode';

  IF p_message IS NOT NULL AND btrim(p_message) <> '' THEN
    UPDATE public.app_config SET value = btrim(p_message)
     WHERE key = 'maintenance_message';
  END IF;

  UPDATE public.app_config
     SET value = COALESCE(p_ends_at::text, '')
   WHERE key = 'maintenance_ends_at';

  -- Only announce a real transition. Re-saving the message while it is
  -- already on must not notify 171 people a second time.
  IF COALESCE(v_was, false) <> COALESCE(p_on, false) THEN
    SELECT COALESCE(NULLIF(btrim(value), ''), 'Maintenance')
      INTO v_msg FROM public.app_config WHERE key = 'maintenance_message';

    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    )
    SELECT p.id,
           CASE WHEN p_on THEN 'Advent Connect is going offline'
                ELSE 'Advent Connect is back' END,
           CASE WHEN p_on THEN v_msg
                ELSE 'Maintenance is finished. Everything is working again — '
                     || 'thank you for your patience.' END,
           'maintenance',
           'maintenance',
           'app_config'
      FROM public.profiles p
     WHERE COALESCE(p.is_banned, false) = false;
  END IF;

  -- All six arguments passed explicitly rather than relying on defaults —
  -- turning the whole app off is exactly the action that must never fail
  -- to be logged because of a signature mismatch.
  PERFORM public.log_admin_action(
    CASE WHEN p_on THEN 'maintenance_on' ELSE 'maintenance_off' END,
    'app_config',
    'maintenance_mode',
    jsonb_build_object('active', COALESCE(v_was, false)),
    jsonb_build_object('active', COALESCE(p_on, false),
                       'ends_at', p_ends_at),
    NULLIF(btrim(COALESCE(p_message, '')), ''));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_maintenance(boolean, text, timestamptz)
  FROM public;
GRANT EXECUTE ON FUNCTION public.admin_set_maintenance(boolean, text, timestamptz)
  TO authenticated;

-- A maintenance notice must survive Sabbath quiet hours. Without this,
-- `suppress_sabbath_notifications()` silently DROPS it — and the one
-- notification you cannot afford to lose is the one saying the app is
-- about to stop working.
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
    'payment_receipt',
    -- The app is about to stop working, or has started again.
    'maintenance'
  );
$function$;

-- ---- The teeth --------------------------------------------------------------
--
-- A trigger per content table rather than an extra clause on each write
-- policy. Two reasons:
--
--  * It is ADDITIVE. Rewriting ~30 existing policies to append
--    `AND NOT public.maintenance_active()` means restating each USING and
--    WITH CHECK expression exactly, and one transcription slip silently
--    widens or breaks access to a table. A trigger touches nothing that
--    already works.
--  * It also covers SECURITY DEFINER RPCs, which bypass RLS entirely.
--    Half the app's writes go through those, so a policy-only approach
--    would have left them wide open during maintenance — the exact
--    "it can be bypassed" the founder asked us to rule out.

CREATE OR REPLACE FUNCTION public.block_during_maintenance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.maintenance_active() THEN
    -- 42501 (insufficient_privilege) so supabase-dart surfaces it as a
    -- PostgrestException the client can recognise rather than a crash.
    RAISE EXCEPTION 'MAINTENANCE_MODE'
      USING ERRCODE = '42501',
            HINT = 'Advent Connect is down for maintenance.';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t text;
  -- User-content tables only.
  --
  -- `notifications` and `app_config` are deliberately ABSENT: switching
  -- maintenance ON writes to both, and a trigger there would make the
  -- feature unable to turn itself on. `profiles` is absent too — blocking
  -- profile writes would break the last-seen heartbeat and lock the
  -- session out in ways that outlive the maintenance window.
  tables text[] := ARRAY[
    'posts', 'post_comments', 'post_reactions', 'post_likes',
    'messages', 'conversations', 'conversation_members',
    'prayers', 'prayer_requests', 'prayer_responses', 'prayer_circles',
    'products', 'orders', 'order_items',
    'events', 'event_rsvps',
    'advent_news', 'announcements', 'announcement_reactions',
    'churches', 'church_admins',
    'jobs', 'job_applications',
    'quiz_scores', 'quiz_challenges', 'quiz_matches',
    'friendships', 'reports', 'stories'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = t
    ) THEN
      EXECUTE format(
        'DROP TRIGGER IF EXISTS maintenance_block ON public.%I', t);
      EXECUTE format(
        'CREATE TRIGGER maintenance_block '
        'BEFORE INSERT OR UPDATE OR DELETE ON public.%I '
        'FOR EACH ROW EXECUTE FUNCTION public.block_during_maintenance()', t);
    END IF;
  END LOOP;
END;
$$;
