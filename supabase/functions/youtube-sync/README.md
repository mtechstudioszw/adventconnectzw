# YouTube sync — Edge Functions

Backs the **Watch** feature. Two functions + a shared helper:

| Function | Role |
|---|---|
| `youtube-sync` | Cron-driven worker: onboard approved channels, backfill catalogs (throttled, resumable), poll live status, renew WebSub leases, reconcile. |
| `youtube-websub` | Public PubSubHubbub callback — YouTube pings it on new/updated/deleted uploads (near-real-time, ≈0 quota). |
| `_shared/youtube.ts` | Data-API helpers shared by both. |

**Compliance:** metadata only. No video/audio/image bytes are fetched, stored, proxied, or re-hosted. The `YOUTUBE_API_KEY` lives only here (server-side), never in the app.

## Secrets (Studio → Project Settings → Edge Functions → Secrets)

| Secret | Used by | Notes |
|---|---|---|
| `YOUTUBE_API_KEY` | both | Google Cloud API key with **YouTube Data API v3** enabled. |
| `CRON_SECRET` | youtube-sync | Gate for the cron caller (passed as `x-cron-secret`). |
| `WEBSUB_CALLBACK_URL` | youtube-sync | The deployed **youtube-websub** URL (so subscriptions point back to it). |
| `WEBSUB_SECRET` | both | Optional. Shared HMAC secret for `X-Hub-Signature` verification. |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | both | Auto-injected. |

## Deploy

```bash
export SUPABASE_ACCESS_TOKEN=<your-management-token>
supabase functions deploy youtube-sync   --project-ref <ref>
supabase functions deploy youtube-websub --project-ref <ref> --no-verify-jwt
```

`youtube-websub` MUST be `--no-verify-jwt` (YouTube's hub is anonymous). Then set `WEBSUB_CALLBACK_URL` to the printed youtube-websub URL and redeploy isn't needed (it's read at runtime).

## Schedule (pg_cron + pg_net)

Apply LIVE via the Management API (real secret/anon are not committed). Placeholders shown:

```sql
-- Every 3 minutes: onboard + backfill slice + live poll + WebSub renew.
select cron.schedule('youtube-sync-tick', '*/3 * * * *', $cron$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/youtube-sync?action=tick',
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer <ANON_KEY>', 'x-cron-secret','<CRON_SECRET>'),
    body := '{}'::jsonb);
$cron$);

-- Daily 04:30 UTC: reconcile (playlist membership + refresh recent/stale).
select cron.schedule('youtube-sync-reconcile', '30 4 * * *', $cron$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/youtube-sync?action=reconcile',
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer <ANON_KEY>', 'x-cron-secret','<CRON_SECRET>'),
    body := '{}'::jsonb);
$cron$);
```

Unschedule: `select cron.unschedule('youtube-sync-tick');`

## Flow

```
admin adds / approves channel  ──► youtube_channel_submissions(status=approved)
        │
   youtube-sync (tick) ── onboard ──► resolve link, create youtube_channels(active),
        │                              fetch playlists, WebSub subscribe
        ├── backfill ──► pull uploads playlist pages (resumable), upsert videos
        ├── live ──────► refresh live/upcoming, set channels.is_live
        └── resubscribe ► renew WebSub leases

new upload on YouTube ──► PubSubHubbub ──► youtube-websub ──► upsert that video (≈0 quota)
```

## Quota

`search.list` (100 units) is only a last-resort in channel resolution. Everything else is 1 unit/call: `playlistItems.list`, `videos.list`, `playlists.list`, `channels.list`. A full backfill ≈ 400 units / 10k videos; steady state is near-zero thanks to WebSub. Default quota is 10,000 units/day.
