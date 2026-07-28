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

`search.list` (100 units) is only a last-resort in channel resolution. Everything else is 1 unit/call: `playlistItems.list`, `videos.list`, `playlists.list`, `channels.list`. A full backfill ≈ 400 units / 10k videos; steady state is near-zero thanks to WebSub. Default quota is 10,000 units/day, resetting at **midnight US Pacific** (07:00 UTC in summer, 08:00 in winter) — *not* at UTC midnight.

Every action is budgeted per run. Keep it that way:

| Action | Budget |
|---|---|
| `onboard` | 3 submissions/tick |
| `backfill` | 2 channels × 4 pages/tick |
| `live` | 1 `videos.list` (≤50 ids)/tick |
| `reconcile` | 4 channels × (1 uploads page + 8 playlists × ≤4 pages)/run |

## When video notifications stop

Diagnosed 2026-07-28: video notifications ceased at 04:39Z while every
other type kept flowing to 09:05Z. The table and triggers were healthy —
the producer had stopped. Three defects, all now fixed in this directory,
each of which alone is enough to silence Watch pushes:

1. **`reconcile` had no budget** — it walked every page of every playlist
   of every channel, daily at 04:30 UTC, in a file whose header promises
   bounded runs. Nine minutes before the stop.
2. **`livePoll` let an API error escape.** Its one quota-spending call sat
   *above* the live-push fan-out in the same function, so any quota error
   took the pushes with it and 500'd the tick.
3. **A 500 mid-tick skipped `resubscribe`.** WebSub leases last 10 days
   and are renewed inside the tick; miss the window and YouTube's hub
   stops delivering, which kills the "📺 New video" push permanently —
   it does not recover when quota resets. This is the one that explains a
   stop that never healed on its own.

After redeploying, confirm the producer is alive:

```sql
-- Leases must be in the FUTURE. Any past/null row means the hub is
-- no longer delivering to us; the next successful tick re-subscribes.
select channel_id, is_live, websub_expires_at, last_synced_at
  from youtube_channels where status = 'active' order by websub_expires_at;

-- Did the cron actually run, and did it return 200?
select jobname, status, return_message, start_time
  from cron.job_run_details
 where jobname like 'youtube-sync%' order by start_time desc limit 20;
```

Then hit `?action=tick` by hand and read the JSON `log` array — every step
now reports its own failure instead of aborting the run.
