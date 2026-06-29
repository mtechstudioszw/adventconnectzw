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
  if (ids.length && API_KEY) {
    try { synced = await fetchAndUpsertVideos(sb, API_KEY, ids); } catch (_) { /* swallow: hub retries */ }
    // NOTE (Phase 4): emit live-start / new-upload push notifications here.
  }

  // Always 200 so the hub doesn't hammer retries.
  return new Response(JSON.stringify({ synced, deleted: deleted.length }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
