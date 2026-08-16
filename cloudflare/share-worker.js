// Advent Connect ZW — Open Graph share Worker
//
// Serves the share/landing pages for products, events, jobs and sellers as
// real `text/html` so WhatsApp/Facebook render a thumbnail AND the in-page
// redirect can open the installed app to the exact item (falling back to the
// Play Store otherwise).
//
// WHY THIS EXISTS: the equivalent Supabase Edge Functions are forced to
// `text/plain` + a CSP sandbox on the default *.supabase.co domain, which
// breaks both the thumbnail and the app redirect. A Cloudflare Worker has no
// such restriction.
//
// Routes (mirror the old Edge Function URLs):
//   /product-share?id=<bigint>
//   /event-share?id=<bigint>
//   /job-share?id=<bigint>
//   /seller-share?id=<auth_user_id>
//   /user-share?id=<profile_id>     (friend QR codes)
//
// Required Worker secrets/vars (see wrangler.toml + README):
//   SUPABASE_URL       e.g. https://eqbyvasteolqyktbqbem.supabase.co
//   SUPABASE_ANON_KEY  the project's anon (publishable) key

const DOWNLOAD_URL =
  "https://play.google.com/store/apps/details?id=io.supabase.adventconnectzw.advent_connect_zw";

const esc = (s) =>
  (s ?? "")
    .toString()
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

// REST read with the anon key (respects RLS — all four are public content).
async function fetchRow(env, table, query) {
  try {
    const res = await fetch(
      `${env.SUPABASE_URL}/rest/v1/${table}?${query}`,
      {
        headers: {
          apikey: env.SUPABASE_ANON_KEY,
          Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
        },
      },
    );
    if (!res.ok) return null;
    const rows = await res.json();
    return Array.isArray(rows) && rows.length ? rows[0] : null;
  } catch (_) {
    return null;
  }
}

// Per-type config: how to fetch the row and map it to the card fields.
const TYPES = {
  "product-share": {
    host: "product",
    kicker: "FOR SALE",
    tag: "MARKETPLACE",
    title: "Marketplace listing",
    description: "A product for sale on Advent Connect ZW marketplace.",
    fetch: (env, id) =>
      fetchRow(
        env,
        "products",
        `id=eq.${encodeURIComponent(id)}&select=title,description,image_urls,price,price_currency,category`,
      ),
    map: (d) => ({
      title: d.title,
      description: d.description,
      image:
        Array.isArray(d.image_urls) && d.image_urls.length
          ? String(d.image_urls[0])
          : "",
      meta:
        d.price && d.price_currency ? `${d.price_currency} ${d.price}` : "",
    }),
  },
  // Feed posts. Public visibility ONLY — the filter is in the query, not in
  // the mapper, so a friends-only or private post returns "not found" rather
  // than leaking its text into a link preview that anyone can unfurl.
  "post-share": {
    host: "post",
    kicker: "POST",
    tag: "COMMUNITY",
    title: "Advent Connect ZW",
    description: "A post from the Seventh-day Adventist community in Zimbabwe.",
    fetch: (env, id) =>
      fetchRow(
        env,
        "posts",
        `id=eq.${encodeURIComponent(id)}&visibility=eq.public` +
          `&select=content,image_url,image_urls`,
      ),
    map: (d) => ({
      title: "Advent Connect ZW",
      description: d.content ?? "",
      image:
        d.image_url ??
        (Array.isArray(d.image_urls) && d.image_urls.length
          ? String(d.image_urls[0])
          : ""),
      meta: "",
    }),
  },
  "event-share": {
    host: "event",
    kicker: "EVENT",
    tag: "EVENTS",
    title: "Advent Connect ZW",
    description: "Join the Seventh-day Adventist community in Zimbabwe.",
    fetch: (env, id) =>
      fetchRow(
        env,
        "events",
        `id=eq.${encodeURIComponent(id)}&select=title,description,cover_photo_url`,
      ),
    map: (d) => ({
      title: d.title,
      description: d.description,
      image: d.cover_photo_url ?? "",
      meta: "",
    }),
  },
  "job-share": {
    host: "job",
    kicker: "JOB OPPORTUNITY",
    tag: "JOBS",
    title: "Job opportunity",
    description: "A job opportunity shared on Advent Connect ZW.",
    fetch: (env, id) =>
      fetchRow(
        env,
        "jobs",
        `id=eq.${encodeURIComponent(id)}&select=title,description,category,province,location`,
      ),
    map: (d) => ({
      title: d.title,
      description: d.description,
      image: "",
      meta: [d.location, d.province].filter(Boolean).join(", "),
    }),
  },
  // Friend QR codes. A phone camera that scans one WITHOUT the app installed
  // used to get `io.supabase.adventconnect://user/<id>` — a scheme nothing on
  // the device handles, so the scan did nothing at all. Pointing the QR at
  // this route instead means the app opens if it is installed, and the Play
  // Store opens if it is not, which is the whole point of handing someone
  // your code.
  //
  // Deliberately NO profile lookup. Every other type here describes public
  // content; a member's name and photo are not that, and this URL is
  // fetchable by anyone who gets the link. A generic card leaks nothing and
  // still redirects correctly.
  //
  // Registered under BOTH `/u` and `/user-share`: the short one is what the
  // QR encodes (every byte costs symbol density at a fixed 210dp), the long
  // one keeps the naming consistent with its siblings and gives anything
  // that guessed the obvious URL somewhere to land.
  u: {
    host: "user",
    kicker: "ADD ME",
    tag: "COMMUNITY",
    title: "Connect on Advent Connect ZW",
    description:
      "Someone shared their Advent Connect ZW code with you. Open the app to see their profile and send a friend request.",
    fetch: async () => null,
    map: () => ({ title: "", description: "", image: "", meta: "" }),
  },
  "seller-share": {
    host: "seller",
    kicker: "STOREFRONT",
    tag: "MARKETPLACE",
    title: "Adventist marketplace seller",
    description: "Browse this store on Advent Connect ZW marketplace.",
    // Sellers are keyed by auth_user_id (matches the app's seller route).
    fetch: (env, id) =>
      fetchRow(
        env,
        "sellers",
        `auth_user_id=eq.${encodeURIComponent(id)}&select=business_name,description,profile_photo_url,cover_photo_url,category`,
      ),
    map: (d) => ({
      title: d.business_name,
      description: d.description,
      image: d.cover_photo_url ?? d.profile_photo_url ?? "",
      meta: "",
    }),
  },
};

function renderHtml(cfg, id, fields) {
  const title = fields.title || cfg.title;
  const description = fields.description || cfg.description;
  const image = fields.image || "";
  const meta = fields.meta || "";
  const appLink = `io.supabase.adventconnect://${cfg.host}/${id}`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(title)} — Advent Connect ZW</title>
  <meta property="og:type" content="website" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
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
    .meta{font-size:18px;color:#1565C0;font-weight:800;margin:0 0 14px}
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
      <div class="tag">${esc(cfg.tag)}</div>
    </div>
    ${image ? `<img class="cover" src="${esc(image)}" alt="" />` : `<div class="cover"></div>`}
    <div class="body">
      <span class="kicker">${esc(cfg.kicker)}</span>
      <h1>${esc(title)}</h1>
      ${meta ? `<p class="meta">${esc(meta)}</p>` : ""}
      <p>${esc(description)}</p>
      <a class="btn" href="${esc(appLink)}">Open in Advent Connect ZW</a>
      <a class="btn-secondary" href="${esc(DOWNLOAD_URL)}">Don't have the app? Get it here</a>
      <div class="muted">Faith • Community • Zimbabwe</div>
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
}

// `/user-share?id=…` is the long-form alias of `/u/…`.
TYPES["user-share"] = TYPES.u;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "");
    // `/u/<id>` carries the id as a path segment; everything else takes it
    // as `?id=`. Splitting on the first slash covers both without a router.
    const slash = path.indexOf("/");
    const slug = slash === -1 ? path : path.slice(0, slash);
    const pathId = slash === -1 ? "" : path.slice(slash + 1);

    const cfg = TYPES[slug];
    if (!cfg) {
      return new Response("Not found", { status: 404 });
    }
    const id = pathId || url.searchParams.get("id") || "";

    let fields = { title: "", description: "", image: "", meta: "" };
    if (id) {
      const row = await cfg.fetch(env, id);
      if (row) fields = cfg.map(row);
    }

    return new Response(renderHtml(cfg, id, fields), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=300",
      },
    });
  },
};
