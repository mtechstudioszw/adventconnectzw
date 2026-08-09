# Advent Connect ZW — Share / Open Graph Worker

> **Redeploy this worker before publishing 1.3.2.** The release adds `/u/<id>`
> for friend QR codes. The currently deployed worker does not have that route,
> so until `wrangler deploy` is run every scanned QR gets a 404 — which is
> worse than the old behaviour, not better. Verify with:
>
> ```
> curl -o /dev/null -w "%{http_code}\n" \
>   "https://advent-share.adventconnectzw.workers.dev/u/test"
> ```
>
> **Also: the workers.dev subdomain changed on 9 Aug 2026**
> (`tanatswamichaelmikuwa` → `adventconnectzw`). Cloudflare leaves no redirect
> behind — the old host stopped resolving, which broke every share link the
> app had ever sent, including ones already sitting in people's WhatsApp
> threads. `kShareBaseUrl` in `lib/config/share_config.dart` has been updated
> to match. Nothing in the app fails loudly when that constant is wrong, so
> curl the host after any change to it.

Serves the share landing pages (`/product-share`, `/event-share`, `/job-share`,
`/seller-share`, `/u`) as real `text/html` so:

1. **WhatsApp / Facebook render a thumbnail** (they read the `og:*` tags), and
2. **tapping the link opens the installed app** to the exact item (the in-page
   JS redirects to `io.supabase.adventconnect://<type>/<id>`, falling back to the
   Play Store after 1.2 s).

## Why not Supabase Edge Functions?

The Supabase platform forces `Content-Type: text/plain` + a CSP `sandbox` on
edge-function responses on the default `*.supabase.co` domain. That makes the
OG tags unreadable to crawlers (no thumbnail) and stops the redirect script
running (link looks broken). A Cloudflare Worker has no such restriction.

## Deploy (one time)

Prereqs: a free Cloudflare account and Node installed.

```bash
cd cloudflare
npm install -g wrangler        # or: npx wrangler ...
wrangler login                 # opens the browser to authorise

# Set the anon key as a secret (get it from Supabase → Project Settings → API
# → "anon public" key). Do NOT use the service_role key.
wrangler secret put SUPABASE_ANON_KEY

wrangler deploy
```

`wrangler deploy` prints the live URL, e.g.
`https://advent-share.<your-account>.workers.dev`.

## Wire the app to it

Set that URL in `lib/config/share_config.dart`:

```dart
const String kShareBaseUrl = 'https://advent-share.<your-account>.workers.dev';
```

(Or a custom domain like `https://share.adventconnectzw.com` if you add one in
Cloudflare and uncomment the `routes` block in `wrangler.toml`.) Then rebuild
the app. All four share buttons already use `share_config.dart`, so that one
line switches every share link over.

## Test

```bash
curl -i "https://advent-share.<your-account>.workers.dev/product-share?id=19"
# Expect: Content-Type: text/html  + <meta property="og:image" ...> populated
```

Paste a share link into WhatsApp to yourself — a thumbnail card should appear,
and tapping it should open the app to that product/event/job/seller.

## Notes

- Reads use the **anon** key and respect RLS — all four content types are
  public listings, so no extra policies are needed.
- The Supabase `*-share` Edge Functions can be left as-is (harmless) or deleted;
  the app no longer points at them once `kShareBaseUrl` is updated.
