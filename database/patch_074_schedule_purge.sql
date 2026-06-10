-- =====================================================================
--  PATCH 074 — schedule the purge-storage edge function daily
--  SQL can't free S3 files, so a cron pings the purge-storage function
--  (verify_jwt=false) which removes expired story photos + orphaned chat
--  media via the storage API. Runs 03:30 UTC, after the DB cleanup.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.schedule(
  'purge-storage',
  '30 3 * * *',
  $$
  SELECT net.http_post(
    url := 'https://eqbyvasteolqyktbqbem.functions.supabase.co/purge-storage',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
