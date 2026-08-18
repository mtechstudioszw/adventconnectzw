// Supabase Edge Function: job-share
//
// Open Graph + Twitter Card landing page for a single job posting.
// Mirrors the event-share pattern — shared on WhatsApp / Facebook
// / X, the link renders a rich preview with the job title and
// description, then deep-links into the app (or the Play Store /
// GitHub Releases fallback).
//
// URL:  https://<ref>.functions.supabase.co/job-share?id=123
// Deploy:  supabase functions deploy job-share --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
// Live Google Play listing — the "Get the app" fallback for visitors
// who tap a shared link without the app installed.
const DOWNLOAD_URL =
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

  let title = "Job opportunity";
  let description =
    "A job listing on Adventist Super App — the SDA community job board.";

  if (id) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
      const { data } = await supabase
        .from("jobs")
        .select("title, description, category, province, city")
        .eq("id", id)
        .maybeSingle();
      if (data) {
        title = data.title ?? title;
        const loc = [data.city, data.province].filter(Boolean).join(", ");
        const cat = data.category ? ` (${data.category})` : "";
        description = data.description
          ? data.description.slice(0, 280)
          : `${loc ? `${loc} — ` : ""}${title}${cat}. Apply via Adventist Super App.`;
      }
    } catch (_) { /* fall through with defaults */ }
  }

  const appLink = `io.supabase.adventconnect://job/${id}`;
  const shareUrl = `${url.origin}${url.pathname}?id=${id}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(title)} — Adventist Super App</title>
  <meta property="og:type" content="website" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:url" content="${esc(shareUrl)}" />
  <meta name="twitter:card" content="summary" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  <style>
    *{box-sizing:border-box}
    body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F5F7FA;color:#1A1A2E;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
    .card{background:#fff;max-width:460px;width:100%;margin:24px;border-radius:24px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.12)}
    .brand{display:flex;align-items:center;gap:10px;padding:14px 18px;background:linear-gradient(135deg,#0D1B3E,#1565C0);color:#fff}
    .brand .badge{width:34px;height:34px;border-radius:10px;background:rgba(255,255,255,.12);border:1.5px solid #C8A951;display:flex;align-items:center;justify-content:center;font-weight:800;color:#C8A951;font-size:14px;letter-spacing:1px}
    .brand .name{font-weight:700;font-size:15px}
    .brand .tag{margin-left:auto;font-size:10.5px;color:rgba(255,255,255,.6);letter-spacing:1.4px}
    .body{padding:22px}
    .kicker{display:inline-block;font-size:10.5px;font-weight:800;letter-spacing:1.6px;color:#1565C0;background:rgba(21,101,192,.10);padding:4px 9px;border-radius:8px;margin-bottom:12px}
    h1{font-size:22px;margin:0 0 10px;line-height:1.25}
    p{color:#555;line-height:1.5;margin:0 0 18px}
    .btn{display:block;text-align:center;background:linear-gradient(135deg,#0D1B3E,#1565C0);color:#fff;text-decoration:none;padding:14px;border-radius:14px;font-weight:700;box-shadow:0 8px 18px rgba(21,101,192,.30)}
    .btn-secondary{display:block;text-align:center;background:#fff;color:#1565C0;text-decoration:none;padding:12px;border-radius:14px;font-weight:700;margin-top:10px;border:1.5px solid rgba(21,101,192,.30)}
    .muted{color:#888;font-size:12px;text-align:center;margin-top:14px;line-height:1.4}
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">
      <div class="badge">A</div>
      <div class="name">Adventist Super App</div>
      <div class="tag">WORLDWIDE</div>
    </div>
    <div class="body">
      <span class="kicker">JOB OPPORTUNITY</span>
      <h1>${esc(title)}</h1>
      <p>${esc(description)}</p>
      <a class="btn" href="${esc(appLink)}">Open in Adventist Super App</a>
      <a class="btn-secondary" href="${esc(DOWNLOAD_URL)}">Don't have the app? Get it here</a>
      <div class="muted">Jobs from the Adventist community around the globe. Apply directly inside the app.</div>
    </div>
  </div>
  <script>
    (function(){
      var t = setTimeout(function(){ window.location.href = ${JSON.stringify(DOWNLOAD_URL)}; }, 1200);
      window.location.href = ${JSON.stringify(appLink)};
      window.addEventListener("pagehide", function(){ clearTimeout(t); });
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
