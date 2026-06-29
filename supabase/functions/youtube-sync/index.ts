// =====================================================================
//  Edge Function: youtube-sync
//
//  The cron-driven worker for the Watch feature. Does ALL YouTube Data
//  API work server-side with the secret YOUTUBE_API_KEY. Bounded per call
//  so a single run never blows the 10,000 units/day quota.
//
//  Actions (?action= or JSON {action}):
//    tick        (default) — onboard + a backfill slice + live poll + resub
//    onboard     — resolve approved submissions -> create+subscribe channels
//    backfill    — pull more of pending channels' upload catalogs (resumable)
//    live        — refresh live/upcoming video statuses + channel is_live
//    resubscribe — renew WebSub leases about to expire
//    reconcile   — map playlist items + refresh recent/stale metadata (daily)
//    sync_videos — {ids:[...]} upsert specific videos (called by youtube-websub)
//
//  Gated by CRON_SECRET (?secret= or x-cron-secret header), like
//  fetch-advent-news. Scheduling lives in pg_cron — see README.
// =====================================================================
// @ts-nocheck
import {
  sbAdmin, ytApi, resolveChannel, upsertChannel, fetchAndUpsertVideos,
  upsertPlaylists, mapPlaylistItems, websub,
} from "../_shared/youtube.ts";

const API_KEY = Deno.env.get("YOUTUBE_API_KEY")!;
const CALLBACK = Deno.env.get("WEBSUB_CALLBACK_URL") ?? "";
const WEBSUB_SECRET = Deno.env.get("WEBSUB_SECRET") ?? "";

// Per-tick budgets — keep each run cheap.
const ONBOARD_PER_TICK = 3;
const BACKFILL_CHANNELS_PER_TICK = 2;
const BACKFILL_PAGES_PER_CHANNEL = 4;   // 4 * 50 = 200 videos/channel/tick

async function onboard(sb): Promise<string[]> {
  const log: string[] = [];
  const { data: subs } = await sb
    .from("youtube_channel_submissions")
    .select("id, link")
    .eq("status", "approved")
    .is("resolved_channel_id", null)
    .limit(ONBOARD_PER_TICK);

  for (const s of subs ?? []) {
    try {
      const res = await resolveChannel(API_KEY, s.link);
      if (!res) { log.push(`onboard ${s.id}: unresolved`); continue; }
      const channelId = await upsertChannel(sb, res);
      await sb.from("youtube_channel_submissions")
        .update({ resolved_channel_id: channelId }).eq("id", s.id);
      await upsertPlaylists(sb, API_KEY, channelId);
      if (CALLBACK) {
        const ok = await websub(channelId, CALLBACK, "subscribe", WEBSUB_SECRET);
        await sb.from("youtube_channels").update({
          websub_expires_at: ok ? new Date(Date.now() + 864000_000).toISOString() : null,
        }).eq("channel_id", channelId);
      }
      log.push(`onboard ${s.id}: ${channelId} ok`);
    } catch (e) {
      log.push(`onboard ${s.id}: ${(e as Error).message}`);
    }
  }
  return log;
}

async function backfill(sb): Promise<string[]> {
  const log: string[] = [];
  const { data: chans } = await sb
    .from("youtube_channels")
    .select("channel_id, uploads_playlist_id, backfill_page_token, thumbnail_url")
    .eq("status", "active").eq("backfill_done", false)
    .not("uploads_playlist_id", "is", null)
    // Round-robin: least-recently-synced first, so one huge channel can't
    // starve the others during the initial backfill.
    .order("last_synced_at", { ascending: true, nullsFirst: true })
    .limit(BACKFILL_CHANNELS_PER_TICK);

  for (const c of chans ?? []) {
    let pageToken = c.backfill_page_token ?? "";
    let pages = 0, imported = 0, done = false;
    try {
      while (pages < BACKFILL_PAGES_PER_CHANNEL) {
        const r = await ytApi("playlistItems", {
          part: "contentDetails", playlistId: c.uploads_playlist_id, maxResults: "50",
          ...(pageToken ? { pageToken } : {}),
        }, API_KEY);
        const ids = (r.items ?? []).map((it: any) => it.contentDetails?.videoId).filter(Boolean);
        imported += await fetchAndUpsertVideos(sb, API_KEY, ids, c.thumbnail_url);
        pages++;
        pageToken = r.nextPageToken ?? "";
        if (!pageToken) { done = true; break; }
      }
      await sb.from("youtube_channels").update({
        backfill_page_token: done ? null : pageToken,
        backfill_done: done,
        last_synced_at: new Date().toISOString(),
      }).eq("channel_id", c.channel_id);
      log.push(`backfill ${c.channel_id}: +${imported}${done ? " (done)" : ""}`);
    } catch (e) {
      log.push(`backfill ${c.channel_id}: ${(e as Error).message}`);
    }
  }
  return log;
}

async function livePoll(sb): Promise<string[]> {
  const log: string[] = [];
  // Refresh every video we currently think is live or upcoming.
  const { data: vids } = await sb
    .from("youtube_videos").select("video_id")
    .in("live_status", ["live", "upcoming"]).limit(50);
  const ids = (vids ?? []).map((v: any) => v.video_id);
  if (ids.length) await fetchAndUpsertVideos(sb, API_KEY, ids);

  // Recompute each channel's denormalised live flag from the videos table.
  const { data: liveVids } = await sb
    .from("youtube_videos").select("channel_id, video_id, title, channel_title")
    .eq("live_status", "live");
  const liveByChannel = new Map<string, { videoId: string; title: string; channelTitle: string }>();
  for (const v of liveVids ?? []) {
    if (!liveByChannel.has(v.channel_id)) {
      liveByChannel.set(v.channel_id, {
        videoId: v.video_id,
        title: v.title ?? "",
        channelTitle: v.channel_title ?? "",
      });
    }
  }

  const { data: chans } = await sb
    .from("youtube_channels")
    .select("channel_id, is_live, live_notified_video_id");
  let pushed = 0;
  for (const c of chans ?? []) {
    const info = liveByChannel.get(c.channel_id);
    const nowLive = !!info;
    if (nowLive !== c.is_live) {
      await sb.from("youtube_channels").update({
        is_live: nowLive,
        live_video_id: nowLive ? info!.videoId : null,
      }).eq("channel_id", c.channel_id);
    }
    // One-time "🔴 live now" push per broadcast (deduped by video id).
    if (nowLive && info!.videoId !== c.live_notified_video_id) {
      try {
        const ch = info!.channelTitle || "A channel";
        await sb.rpc("youtube_fanout_notification", {
          p_title: `🔴 ${ch} is live`,
          p_body: `${ch} has just started a live stream${info!.title ? `: ${info!.title}` : ""}. Tap to watch now.`,
          p_video_id: info!.videoId,
        });
        await sb.from("youtube_channels")
          .update({ live_notified_video_id: info!.videoId })
          .eq("channel_id", c.channel_id);
        pushed++;
      } catch (e) {
        log.push(`live push ${c.channel_id}: ${(e as Error).message}`);
      }
    }
  }
  log.push(`live: checked ${ids.length} video(s), ${liveByChannel.size} live, ${pushed} pushed`);
  return log;
}

async function resubscribe(sb): Promise<string[]> {
  if (!CALLBACK) return ["resub: no WEBSUB_CALLBACK_URL"];
  const soon = new Date(Date.now() + 86400_000).toISOString(); // < 1 day left
  const { data: chans } = await sb
    .from("youtube_channels").select("channel_id")
    .eq("status", "active").or(`websub_expires_at.lt.${soon},websub_expires_at.is.null`).limit(20);
  let n = 0;
  for (const c of chans ?? []) {
    const ok = await websub(c.channel_id, CALLBACK, "subscribe", WEBSUB_SECRET);
    if (ok) {
      await sb.from("youtube_channels").update({
        websub_expires_at: new Date(Date.now() + 864000_000).toISOString(),
      }).eq("channel_id", c.channel_id);
      n++;
    }
  }
  return [`resub: renewed ${n}`];
}

async function reconcile(sb): Promise<string[]> {
  const log: string[] = [];
  const { data: chans } = await sb
    .from("youtube_channels").select("channel_id, uploads_playlist_id, thumbnail_url")
    .eq("status", "active").eq("backfill_done", true);
  for (const c of chans ?? []) {
    try {
      // Catch anything WebSub missed: re-pull the newest page of uploads.
      if (c.uploads_playlist_id) {
        const r = await ytApi("playlistItems", {
          part: "contentDetails", playlistId: c.uploads_playlist_id, maxResults: "50",
        }, API_KEY);
        const ids = (r.items ?? []).map((it: any) => it.contentDetails?.videoId).filter(Boolean);
        await fetchAndUpsertVideos(sb, API_KEY, ids, c.thumbnail_url);
      }
      // Refresh playlist membership (categories).
      const { data: pls } = await sb.from("youtube_playlists").select("playlist_id").eq("channel_id", c.channel_id);
      for (const p of pls ?? []) await mapPlaylistItems(sb, API_KEY, p.playlist_id);
      log.push(`reconcile ${c.channel_id}: ok`);
    } catch (e) {
      log.push(`reconcile ${c.channel_id}: ${(e as Error).message}`);
    }
  }
  return log;
}

Deno.serve(async (req) => {
  // CRON_SECRET gate.
  const secret = Deno.env.get("CRON_SECRET");
  const url = new URL(req.url);
  if (secret) {
    const got = url.searchParams.get("secret") || req.headers.get("x-cron-secret");
    if (got !== secret) return new Response("forbidden", { status: 403 });
  }
  if (!API_KEY) return new Response("YOUTUBE_API_KEY not set", { status: 500 });

  let body: any = {};
  try { if (req.method === "POST") body = await req.json(); } catch (_) { /* empty */ }
  const action = url.searchParams.get("action") || body.action || "tick";
  const sb = sbAdmin();
  const out: string[] = [];

  try {
    switch (action) {
      case "onboard":     out.push(...await onboard(sb)); break;
      case "backfill":    out.push(...await backfill(sb)); break;
      case "live":        out.push(...await livePoll(sb)); break;
      case "resubscribe": out.push(...await resubscribe(sb)); break;
      case "reconcile":   out.push(...await reconcile(sb)); break;
      case "sync_videos": {
        const ids: string[] = body.ids ?? [];
        const n = ids.length ? await fetchAndUpsertVideos(sb, API_KEY, ids) : 0;
        out.push(`sync_videos: ${n}`);
        break;
      }
      case "tick":
      default:
        out.push(...await onboard(sb));
        out.push(...await backfill(sb));
        out.push(...await livePoll(sb));
        out.push(...await resubscribe(sb));
    }
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: (e as Error).message, log: out }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ ok: true, action, log: out }), {
    headers: { "Content-Type": "application/json" },
  });
});
