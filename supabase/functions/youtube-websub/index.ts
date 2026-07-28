// =====================================================================
//  Edge Function: youtube-websub
//
//  Public PubSubHubbub (WebSub) callback for monitored channels. YouTube
//  pings this within seconds of a new/updated/deleted upload — near-real-
//  time sync at ≈0 API quota.
//
//    GET  -> hub verification: echo hub.challenge.
//    POST -> Atom feed: extract video ids, upsert them (or delete on
//            at:deleted-entry, per the YouTube data-deletion rule).
//
//  Subscriptions are created/renewed by youtube-sync (it sends this
//  function's URL as hub.callback). Set WEBSUB_CALLBACK_URL on youtube-sync
//  to THIS function's deployed URL. Optional shared WEBSUB_SECRET enables
//  X-Hub-Signature verification.
//
//  verify_jwt MUST be off for this function (YouTube's hub is anonymous):
//      supabase functions deploy youtube-websub --no-verify-jwt
// =====================================================================
// @ts-nocheck
import { sbAdmin, fetchAndUpsertVideos } from "../_shared/youtube.ts";

const API_KEY = Deno.env.get("YOUTUBE_API_KEY")!;
const WEBSUB_SECRET = Deno.env.get("WEBSUB_SECRET") ?? "";

async function verifySignature(req: Request, raw: string): Promise<boolean> {
  if (!WEBSUB_SECRET) return true; // not enforced
  const header = req.headers.get("x-hub-signature") ?? "";
  const [, sig] = header.split("=");
  if (!sig) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(WEBSUB_SECRET),
    { name: "HMAC", hash: "SHA-1" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === sig;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // ---- Hub verification handshake ----
  if (req.method === "GET") {
    const challenge = url.searchParams.get("hub.challenge");
    if (challenge) return new Response(challenge, { status: 200 });
    return new Response("ok", { status: 200 });
  }

  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const raw = await req.text();
  if (!(await verifySignature(req, raw))) return new Response("bad signature", { status: 202 });

  const sb = sbAdmin();

  // Deleted videos -> remove our stored copy (data-deletion compliance).
  const deleted = [...raw.matchAll(/ref="yt:video:([\w-]{6,})"/g)].map((m) => m[1]);
  if (deleted.length) {
    await sb.from("youtube_videos").delete().in("video_id", deleted);
  }

  // New / updated videos.
  const ids = [...raw.matchAll(/<yt:videoId>([\w-]{6,})<\/yt:videoId>/g)]
    .map((m) => m[1])
    .filter((id) => !deleted.includes(id));

  let synced = 0;
  let syncError = "";
  if (ids.length && API_KEY) {
    // The old comment here said "swallow: hub retries" — but this handler
    // always returned 200, so the hub never retried. A quota error meant
    // the row was never upserted, the fan-out below found nothing, and
    // that upload's push was lost permanently. Record the failure and let
    // the response decide (see the 503 at the bottom).
    try {
      synced = await fetchAndUpsertVideos(sb, API_KEY, ids);
    } catch (e) {
      syncError = (e as Error).message;
    }
    // "New video" push. Spam-safe by construction:
    //   - only genuinely-new uploads (upload_notified_at IS NULL),
    //   - only recent ones (<6h) so a backfill/re-sync of old videos is silent,
    //   - NON-live only (live starts are notified by youtube-sync's live path),
    //   - at most ONE push per channel per 12h (rate limit), so a burst of
    //     uploads can never flood every user.
    // Best-effort throughout — a failure here must never break the hub's 200.
    try {
      const sixHoursAgo = new Date(Date.now() - 6 * 3600e3).toISOString();
      const twelveHoursAgo = new Date(Date.now() - 12 * 3600e3).toISOString();
      const nowIso = new Date().toISOString();
      const { data: fresh } = await sb
        .from("youtube_videos")
        .select("video_id, title, channel_id, channel_title, published_at")
        .in("video_id", ids)
        .eq("live_status", "none")
        .is("upload_notified_at", null)
        .gt("published_at", sixHoursAgo)
        .order("published_at", { ascending: false });
      const seenChannel = new Set<string>();
      for (const v of fresh ?? []) {
        if (seenChannel.has(v.channel_id)) continue; // one per channel/delivery
        seenChannel.add(v.channel_id);
        const { data: recent } = await sb
          .from("youtube_videos")
          .select("video_id")
          .eq("channel_id", v.channel_id)
          .gt("upload_notified_at", twelveHoursAgo)
          .limit(1);
        if (recent && recent.length) continue; // rate-limited this channel
        const ch = v.channel_title || "A channel";
        try {
          await sb.rpc("youtube_fanout_notification", {
            p_title: `📺 New video from ${ch}`,
            p_body: v.title
              ? `${ch} just posted: ${v.title}. Tap to watch.`
              : `${ch} just posted a new video. Tap to watch.`,
            p_video_id: v.video_id,
          });
          await sb.from("youtube_videos")
            .update({ upload_notified_at: nowIso })
            .eq("video_id", v.video_id);
        } catch (_) { /* per-video best effort */ }
      }
    } catch (_) { /* notifications are best-effort */ }
  }

  // 200 for everything we handled — a well-behaved subscriber, and no
  // retry storms. The one exception is a failed YouTube fetch: that is
  // exactly the transient case retries exist for, and swallowing it
  // silently dropped the "new video" push for that upload entirely.
  if (syncError) {
    return new Response(JSON.stringify({ synced, error: syncError }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ synced, deleted: deleted.length }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
