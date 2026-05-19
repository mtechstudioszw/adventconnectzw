-- =====================================================================
--  PATCH 014 — Admin-broadcast announcements
--
--  WHY:  The external admin panel needs a way to push a single
--        message to every Advent Connect ZW user (release notes,
--        community alerts, urgent updates). This table holds those
--        broadcasts; the mobile app reads it on launch / pull-to-
--        refresh and surfaces unread ones as an in-app banner /
--        notification entry.
--
--        Push-notification delivery (FCM) can be wired later via an
--        Edge Function fired by INSERT trigger — for v1 the in-app
--        surface is enough.
--
--  RLS:   Anyone authenticated can read. Only the service-role
--        (admin panel) can insert / update / delete — there is no
--        end-user INSERT policy by design.
--
--  PREREQUISITES: schema.sql + patch_001..patch_013 already applied.
--  IDEMPOTENT:    yes.
-- =====================================================================


CREATE TABLE IF NOT EXISTS public.admin_announcements (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title        TEXT NOT NULL CHECK (char_length(title) BETWEEN 2 AND 120),
  body         TEXT NOT NULL CHECK (char_length(body) BETWEEN 2 AND 2000),
  audience     TEXT NOT NULL DEFAULT 'all'
                 CHECK (audience IN ('all', 'business', 'personal')),
  -- Severity nudges the UI: 'info' is a quiet banner, 'urgent' is the
  -- red urgent strip the home screen already supports.
  severity     TEXT NOT NULL DEFAULT 'info'
                 CHECK (severity IN ('info', 'urgent')),
  created_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_admin_announcements_recent
  ON public.admin_announcements (created_at DESC);


ALTER TABLE public.admin_announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "announcements_select_all" ON public.admin_announcements;

CREATE POLICY "announcements_select_all" ON public.admin_announcements
  FOR SELECT USING (auth.role() = 'authenticated');

-- NB: no INSERT / UPDATE / DELETE policy — the admin panel uses
-- the service role for writes, which bypasses RLS.


-- =====================================================================
--  END OF PATCH 014
-- =====================================================================
