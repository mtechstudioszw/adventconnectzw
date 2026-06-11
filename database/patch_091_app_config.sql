-- =====================================================================
--  PATCH 091 — app_config (force-update minimum build)
--
--  A tiny key/value config the app reads on launch. min_build_android is
--  the lowest Android versionCode allowed to run; when the installed
--  build is below it, the app shows a blocking "Update required" screen.
--  Seeded at 1 so it never blocks the current build — bump it (to the
--  versionCode you want to make mandatory) whenever you must force an
--  update. Readable by everyone (checked before sign-in too).
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.app_config (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_config_read ON public.app_config;
CREATE POLICY app_config_read ON public.app_config
  FOR SELECT TO anon, authenticated USING (true);

INSERT INTO public.app_config (key, value) VALUES
  ('min_build_android', '1'),
  ('min_build_ios', '1')
ON CONFLICT (key) DO NOTHING;
