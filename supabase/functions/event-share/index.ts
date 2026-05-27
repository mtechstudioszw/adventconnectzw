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
// Until the Play Store + iOS App Store listings ship, the "Get the
// app" fallback points at the GitHub Releases page where each push
// to main publishes a debug APK (.github/workflows/build-apk.yml).
// Replace with the Play Store / web app URL once those exist.
const DOWNLOAD_URL =
  "https://adventconnectzw.netlify.app/download.html";

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
    *{box-sizing:border-box}
    body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F5F7FA;color:#1A1A2E;margin:0;padding:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
    .card{background:#fff;max-width:460px;width:100%;margin:24px;border-radius:24px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.12)}
    .brand{display:flex;align-items:center;gap:10px;padding:14px 18px;background:linear-gradient(135deg,#0D1B3E,#1565C0);color:#fff}
    .brand .badge{width:34px;height:34px;border-radius:10px;background:rgba(255,255,255,.12);border:1.5px solid #C8A951;display:flex;align-items:center;justify-content:center;font-weight:800;color:#C8A951;font-size:14px;letter-spacing:1px}
    .brand .name{font-weight:700;font-size:15px}
    .brand .tag{margin-left:auto;font-size:10.5px;color:rgba(255,255,255,.6);letter-spacing:1.4px}
    .cover{width:100%;aspect-ratio:16/9;object-fit:cover;background:#0D1B3E;display:block}
    .body{padding:22px}
    h1{font-size:20px;margin:0 0 8px;line-height:1.3}
    p{color:#555;line-height:1.45;margin:0 0 18px}
    .btn{display:block;text-align:center;background:linear-gradient(135deg,#0D1B3E,#1565C0);color:#fff;text-decoration:none;padding:14px;border-radius:14px;font-weight:700;box-shadow:0 8px 18px rgba(21,101,192,.30)}
    .btn-secondary{display:block;text-align:center;background:#fff;color:#1565C0;text-decoration:none;padding:12px;border-radius:14px;font-weight:700;margin-top:10px;border:1.5px solid rgba(21,101,192,.30)}
    .muted{color:#888;font-size:12px;text-align:center;margin-top:14px;line-height:1.4}
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">
      <div class="badge">A</div>
      <div class="name">Advent Connect ZW</div>
      <div class="tag">ZIMBABWE</div>
    </div>
    ${image ? `<img class="cover" src="${esc(image)}" alt="" />` : `<div class="cover"></div>`}
    <div class="body">
      <h1>${esc(title)}</h1>
      <p>${esc(description)}</p>
      <a class="btn" href="${esc(appLink)}">Open in Advent Connect ZW</a>
      <a class="btn-secondary" href="${esc(DOWNLOAD_URL)}">Don't have the app? Get it here</a>
      <div class="muted">The Christian community app for Zimbabwe. Connect with members, find churches, share prayers and events.</div>
    </div>
  </div>
  <script>
    // Try the app first; if nothing handles the scheme within 1.2s,
    // send the user to the download page (GitHub Releases for now,
    // Play Store once published).
    (function () {
      var t = setTimeout(function () {
        window.location.href = ${JSON.stringify(DOWNLOAD_URL)};
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
