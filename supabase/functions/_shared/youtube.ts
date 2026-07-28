// =====================================================================
//  Shared YouTube Data API helpers for the youtube-sync + youtube-websub
//  edge functions.
//
//  COMPLIANCE: we only ever read METADATA via the official Data API v3
//  using the server-only YOUTUBE_API_KEY. We never fetch/store/proxy the
//  media itself — playback is the official IFrame player on-device.
// =====================================================================
// @ts-nocheck
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const API = "https://www.googleapis.com/youtube/v3";

export function sbAdmin(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function ytApi(
  path: string,
  params: Record<string, string>,
  apiKey: string,
): Promise<any> {
  const qs = new URLSearchParams({ ...params, key: apiKey }).toString();
  const res = await fetch(`${API}/${path}?${qs}`);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`YouTube ${path} ${res.status}: ${body.slice(0, 300)}`);
  }
  return res.json();
}

// ISO-8601 duration (PT#H#M#S) -> seconds. Live items are often "P0D"/empty.
export function parseISODuration(iso: string | undefined): number {
  if (!iso) return 0;
  const m = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!m) return 0;
  return (+(m[1] || 0)) * 3600 + (+(m[2] || 0)) * 60 + (+(m[3] || 0));
}

function bestThumb(thumbs: any): string | null {
  if (!thumbs) return null;
  return (thumbs.maxres || thumbs.standard || thumbs.high ||
          thumbs.medium || thumbs.default)?.url ?? null;
}

// Map a videos.list item to our row shape.
function videoRow(item: any, channelThumb?: string | null) {
  const sn = item.snippet ?? {};
  const cd = item.contentDetails ?? {};
  const ls = item.liveStreamingDetails;
  const broadcast = sn.liveBroadcastContent ?? "none"; // none | live | upcoming
  let kind = "video", live_status = "none";
  if (broadcast === "live") { kind = "live"; live_status = "live"; }
  else if (broadcast === "upcoming") { kind = "upcoming"; live_status = "upcoming"; }
  else if (ls && ls.actualEndTime) { kind = "video"; live_status = "ended"; }
  return {
    video_id: item.id,
    channel_id: sn.channelId,
    channel_title: sn.channelTitle ?? "",
    channel_thumb_url: channelThumb ?? null,
    title: (sn.title ?? "").slice(0, 300),
    description: (sn.description ?? "").slice(0, 2000),
    thumbnail_url: bestThumb(sn.thumbnails),
    published_at: sn.publishedAt ?? null,
    duration_seconds: parseISODuration(cd.duration),
    kind,
    live_status,
    scheduled_start_at: ls?.scheduledStartTime ?? null,
    actual_start_at: ls?.actualStartTime ?? null,
    view_count: item.statistics?.viewCount ? Number(item.statistics.viewCount) : null,
    fetched_at: new Date().toISOString(),
  };
}

// Resolve a raw channel link / @handle / UC id to a channel resource.
export async function resolveChannel(apiKey: string, link: string): Promise<any | null> {
  const part = "snippet,contentDetails,statistics";
  const raw = (link || "").trim();

  // Direct channel id
  let m = raw.match(/UC[A-Za-z0-9_-]{20,}/);
  if (m) {
    const r = await ytApi("channels", { part, id: m[0] }, apiKey);
    return r.items?.[0] ?? null;
  }
  // @handle (bare or in a URL)
  m = raw.match(/@([A-Za-z0-9._-]+)/);
  if (m) {
    const r = await ytApi("channels", { part, forHandle: "@" + m[1] }, apiKey);
    if (r.items?.[0]) return r.items[0];
  }
  // /user/NAME legacy
  m = raw.match(/\/user\/([A-Za-z0-9._-]+)/);
  if (m) {
    const r = await ytApi("channels", { part, forUsername: m[1] }, apiKey);
    if (r.items?.[0]) return r.items[0];
  }
  // Last resort: search (100 units) for /c/custom or plain names.
  const term = raw.replace(/^https?:\/\/(www\.)?youtube\.com\/(c\/)?/i, "").replace(/\/.*$/, "");
  if (term) {
    const s = await ytApi("search", { part: "snippet", type: "channel", q: term, maxResults: "1" }, apiKey);
    const id = s.items?.[0]?.snippet?.channelId;
    if (id) {
      const r = await ytApi("channels", { part, id }, apiKey);
      return r.items?.[0] ?? null;
    }
  }
  return null;
}

export async function upsertChannel(sb: SupabaseClient, res: any): Promise<string> {
  const sn = res.snippet ?? {};
  const uploads = res.contentDetails?.relatedPlaylists?.uploads ?? null;
  await sb.from("youtube_channels").upsert({
    channel_id: res.id,
    title: sn.title ?? "",
    handle: sn.customUrl ?? null,
    description: (sn.description ?? "").slice(0, 2000),
    thumbnail_url: bestThumb(sn.thumbnails),
    uploads_playlist_id: uploads,
    subscriber_count: res.statistics?.subscriberCount ? Number(res.statistics.subscriberCount) : null,
    status: "active",
    approved_at: new Date().toISOString(),
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "channel_id" });
  return res.id;
}

// Fetch full metadata for a batch of video ids and upsert them.
export async function fetchAndUpsertVideos(
  sb: SupabaseClient, apiKey: string, ids: string[], channelThumb?: string | null,
): Promise<number> {
  let n = 0;
  for (let i = 0; i < ids.length; i += 50) {
    const chunk = ids.slice(i, i + 50).filter(Boolean);
    if (!chunk.length) continue;
    const r = await ytApi("videos", {
      part: "snippet,contentDetails,liveStreamingDetails,statistics",
      id: chunk.join(","), maxResults: "50",
    }, apiKey);
    const rows = (r.items ?? []).map((it: any) => videoRow(it, channelThumb)).filter((x) => x.channel_id);
    if (rows.length) {
      await sb.from("youtube_videos").upsert(rows, { onConflict: "video_id" });
      n += rows.length;
    }
  }
  return n;
}

// Re-fetch a set of videos and PRUNE any that YouTube no longer returns
// (deleted / made private) — the YouTube ToS data-refresh/30-day rule.
// videos.list silently omits ids that no longer exist, so anything we
// asked for but didn't get back is removed from our copy.
export async function refreshAndPrune(
  sb: SupabaseClient, apiKey: string, ids: string[],
): Promise<{ refreshed: number; deleted: number }> {
  if (!ids.length) return { refreshed: 0, deleted: 0 };
  const found = new Set<string>();
  let refreshed = 0;
  for (let i = 0; i < ids.length; i += 50) {
    const chunk = ids.slice(i, i + 50).filter(Boolean);
    if (!chunk.length) continue;
    const r = await ytApi("videos", {
      part: "snippet,contentDetails,liveStreamingDetails,statistics",
      id: chunk.join(","), maxResults: "50",
    }, apiKey);
    const rows = (r.items ?? []).map((it: any) => videoRow(it)).filter((x) => x.channel_id);
    for (const it of r.items ?? []) found.add(it.id);
    if (rows.length) {
      await sb.from("youtube_videos").upsert(rows, { onConflict: "video_id" });
      refreshed += rows.length;
    }
  }
  const missing = ids.filter((id) => !found.has(id));
  if (missing.length) {
    await sb.from("youtube_videos").delete().in("video_id", missing);
  }
  return { refreshed, deleted: missing.length };
}

// Pull this channel's playlists (used as Watch-tab categories).
export async function upsertPlaylists(sb: SupabaseClient, apiKey: string, channelId: string) {
  let pageToken = "";
  let order = 0;
  do {
    const r = await ytApi("playlists", {
      part: "snippet,contentDetails", channelId, maxResults: "50",
      ...(pageToken ? { pageToken } : {}),
    }, apiKey);
    const rows = (r.items ?? []).map((p: any) => ({
      playlist_id: p.id,
      channel_id: channelId,
      title: (p.snippet?.title ?? "").slice(0, 200),
      description: (p.snippet?.description ?? "").slice(0, 500),
      thumbnail_url: bestThumb(p.snippet?.thumbnails),
      item_count: p.contentDetails?.itemCount ?? 0,
      sort_order: order++,
    }));
    if (rows.length) await sb.from("youtube_playlists").upsert(rows, { onConflict: "playlist_id" });
    pageToken = r.nextPageToken ?? "";
  } while (pageToken);
}

// Map a playlist's video membership (for category filtering).
// Refresh a playlist's membership (which videos are in which series).
//
// `maxPages` is a hard quota guard, not a nicety: this used to walk every
// page of every playlist of every channel on each reconcile run, which is
// unbounded YouTube spend on a daily job. Positions are stable from the
// front of the playlist, so the first pages are the ones worth having.
export async function mapPlaylistItems(
  sb: SupabaseClient, apiKey: string, playlistId: string, maxPages = 4,
) {
  let pageToken = "";
  let pos = 0;
  let pages = 0;
  do {
    const r = await ytApi("playlistItems", {
      part: "contentDetails", playlistId, maxResults: "50",
      ...(pageToken ? { pageToken } : {}),
    }, apiKey);
    const rows = (r.items ?? [])
      .map((it: any) => it.contentDetails?.videoId)
      .filter(Boolean)
      .map((vid: string) => ({ playlist_id: playlistId, video_id: vid, position: pos++ }));
    if (rows.length) await sb.from("youtube_playlist_items").upsert(rows, { onConflict: "playlist_id,video_id" });
    pageToken = r.nextPageToken ?? "";
  } while (pageToken && ++pages < maxPages);
}

// Subscribe / unsubscribe a channel's upload feed via PubSubHubbub (WebSub).
export async function websub(
  channelId: string, callbackUrl: string, mode: "subscribe" | "unsubscribe" = "subscribe",
  secret?: string, leaseSeconds = 864000, // ~10 days
): Promise<boolean> {
  const form = new URLSearchParams({
    "hub.mode": mode,
    "hub.topic": `https://www.youtube.com/xml/feeds/videos.xml?channel_id=${channelId}`,
    "hub.callback": callbackUrl,
    "hub.verify": "async",
    "hub.lease_seconds": String(leaseSeconds),
  });
  if (secret) form.set("hub.secret", secret);
  const res = await fetch("https://pubsubhubbub.appspot.com/subscribe", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  return res.status === 202 || res.ok;
}
