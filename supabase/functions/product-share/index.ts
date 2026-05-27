// Supabase Edge Function: product-share
//
// Open Graph + Twitter Card landing page for a single marketplace
// product. Mirrors event-share / job-share.
//
// URL:  https://<ref>.functions.supabase.co/product-share?id=123
// Deploy:  supabase functions deploy product-share --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const DOWNLOAD_URL =
  "https://advent-connect-zw.netlify.app/download.html";

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

  let title = "Marketplace listing";
  let description = "A product for sale on Advent Connect ZW marketplace.";
  let image = "";
  let price = "";

  if (id) {
    try {
      const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
      const { data } = await supabase
        .from("products")
        .select("title, description, image_urls, price, currency, category")
        .eq("id", id)
        .maybeSingle();
      if (data) {
        title = data.title ?? title;
        description = data.description ?? description;
        const imgs = data.image_urls;
        if (Array.isArray(imgs) && imgs.length > 0) image = String(imgs[0]);
        if (data.price && data.currency) {
          price = `${data.currency} ${data.price}`;
        }
      }
    } catch (_) { /* fall through with defaults */ }
  }

  const appLink = `io.supabase.adventconnect://product/${id}`;
  const shareUrl = `${url.origin}${url.pathname}?id=${id}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(title)} — Advent Connect ZW</title>
  <meta property="og:type" content="product" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:url" content="${esc(shareUrl)}" />
  ${image ? `<meta property="og:image" content="${esc(image)}" />` : ""}
  <meta name="twitter:card" content="${image ? "summary_large_image" : "summary"}" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  ${image ? `<meta name="twitter:image" content="${esc(image)}" />` : ""}
  <style>
    *{box-sizing:border-box}
    body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F5F7FA;color:#1A1A2E;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
    .card{background:#fff;max-width:460px;width:100%;margin:24px;border-radius:24px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.12)}
    .brand{display:flex;align-items:center;gap:10px;padding:14px 18px;background:linear-gradient(135deg,#0D1B3E,#1565C0);color:#fff}
    .brand .badge{width:34px;height:34px;border-radius:10px;background:rgba(255,255,255,.12);border:1.5px solid #C8A951;display:flex;align-items:center;justify-content:center;font-weight:800;color:#C8A951;font-size:14px;letter-spacing:1px}
    .brand .name{font-weight:700;font-size:15px}
    .brand .tag{margin-left:auto;font-size:10.5px;color:rgba(255,255,255,.6);letter-spacing:1.4px}
    .cover{width:100%;aspect-ratio:1/1;object-fit:cover;background:#0D1B3E;display:block}
    .body{padding:22px}
    .kicker{display:inline-block;font-size:10.5px;font-weight:800;letter-spacing:1.6px;color:#1565C0;background:rgba(21,101,192,.10);padding:4px 9px;border-radius:8px;margin-bottom:12px}
    h1{font-size:22px;margin:0 0 6px;line-height:1.25}
    .price{font-size:18px;color:#1565C0;font-weight:800;margin:0 0 14px}
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
      <div class="name">Advent Connect ZW</div>
      <div class="tag">MARKETPLACE</div>
    </div>
    ${image ? `<img class="cover" src="${esc(image)}" alt="" />` : `<div class="cover"></div>`}
    <div class="body">
      <span class="kicker">FOR SALE</span>
      <h1>${esc(title)}</h1>
      ${price ? `<p class="price">${esc(price)}</p>` : ""}
      <p>${esc(description)}</p>
      <a class="btn" href="${esc(appLink)}">Open in Advent Connect ZW</a>
      <a class="btn-secondary" href="${esc(DOWNLOAD_URL)}">Don't have the app? Get it here</a>
      <div class="muted">Buy + sell within the SDA community in Zimbabwe.</div>
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
