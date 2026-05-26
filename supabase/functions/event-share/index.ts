// Supabase Edge Function: event-share
//
// Serves an HTML page with Open Graph + Twitter Card meta tags for a
// single event, so links shared to WhatsApp / Facebook / X render a
// rich preview (event title, description, and cover-photo thumbnail).
//
// The page also tries to deep-link straight into the app via the
// io.supabase.adventconnect:// custom scheme, falling back to the
// Play Store after a short delay if the app isn't installed.
//
// URL shape:  https://<ref>.functions.supabase.co/event-share?id=123
//
// Deploy:  supabase functions deploy event-share --no-verify-jwt
// (must be --no-verify-jwt so social crawlers can fetch it unauthed)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=io.supabase.adventconnectzw.advent_connect_zw";

function esc(s: string): string {
  return (s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const id = url.searchParams.get("id") ?? "";

  let title = "Advent Connect ZW";
  let description = "Join the Seventh-day Adventist community in Zimbabwe.";
  let image = "";

  if (id) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
      const { data } = await supabase
        .from("events")
        .select("title, description, cover_photo_url")
        .eq("id", id)
        .maybeSingle();
      if (data) {
        title = data.title ?? title;
        description = data.description ?? description;
        image = data.cover_photo_url ?? "";
      }
    } catch (_) {
      // fall through with defaults
    }
  }

  const appLink = `io.supabase.adventconnect://event/${id}`;
  const shareUrl = `${url.origin}${url.pathname}?id=${id}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(title)}</title>

  <!-- Open Graph -->
  <meta property="og:type" content="website" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:url" content="${esc(shareUrl)}" />
  ${image ? `<meta property="og:image" content="${esc(image)}" />` : ""}

  <!-- Twitter Card -->
  <meta name="twitter:card" content="${image ? "summary_large_image" : "summary"}" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  ${image ? `<meta name="twitter:image" content="${esc(image)}" />` : ""}

  <style>
    body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F5F7FA;color:#1A1A2E;margin:0;padding:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
    .card{background:#fff;max-width:460px;margin:24px;border-radius:20px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.12)}
    .cover{width:100%;aspect-ratio:16/9;object-fit:cover;background:#0D1B3E}
    .body{padding:22px}
    h1{font-size:20px;margin:0 0 8px}
    p{color:#555;line-height:1.45;margin:0 0 18px}
    .btn{display:block;text-align:center;background:#1565C0;color:#fff;text-decoration:none;padding:14px;border-radius:14px;font-weight:700}
    .muted{color:#888;font-size:12px;text-align:center;margin-top:12px}
  </style>
</head>
<body>
  <div class="card">
    ${image ? `<img class="cover" src="${esc(image)}" alt="" />` : `<div class="cover"></div>`}
    <div class="body">
      <h1>${esc(title)}</h1>
      <p>${esc(description)}</p>
      <a class="btn" href="${esc(appLink)}">Open in Advent Connect ZW</a>
      <div class="muted">Don't have the app? You'll be taken to the Play Store.</div>
    </div>
  </div>
  <script>
    // Try the app first; if nothing handles the scheme within 1.2s,
    // send the user to the Play Store.
    (function () {
      var t = setTimeout(function () {
        window.location.href = ${JSON.stringify(PLAY_STORE_URL)};
      }, 1200);
      window.location.href = ${JSON.stringify(appLink)};
      window.addEventListener("pagehide", function () { clearTimeout(t); });
    })();
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
});
