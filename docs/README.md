# Advent Connect ZW — public site

Static site that ships the legal pages (Terms / Privacy / Community
Guidelines), an About page, and a Download landing. Hosted on
**Netlify** so the GitHub repo can stay private while the docs are
public. Free tier: unlimited bandwidth, 100 GB/month, custom domain
support, no card required.

## Setup (one-time, ~3 minutes)

1. Open https://app.netlify.com/signup → sign up with your GitHub
   account (free).
2. After signup → **Add new site** → **Import an existing project**.
3. **Connect to Git provider** → GitHub → authorise → pick the
   private `adventconnectzw` repo. (Netlify reads private repos
   fine.)
4. **Site settings:**
   - Branch to deploy: `main`
   - Base directory: leave empty
   - Build command: leave empty
   - **Publish directory: `docs`**  ← important
5. **Site name** (under Site configuration → General → Change site
   name): set it to exactly `advent-connect-zw` so the URL becomes
   `https://advent-connect-zw.netlify.app/`. The Edge Functions in
   this repo are already configured to point there.
6. Click **Deploy**. First build takes ~30 seconds. Subsequent
   pushes that touch `docs/` re-deploy automatically.

## Resulting URLs

| Page | URL |
|---|---|
| Home | https://advent-connect-zw.netlify.app/ |
| **Terms of Service** | …/terms.html ← **Play Store listing field** |
| **Privacy Policy** | …/privacy.html ← **Play Store listing field** |
| Community Guidelines | …/guidelines.html |
| About | …/about.html |
| Download | …/download.html |

The Privacy Policy URL is the one Google Play Console asks for at
submission time — paste `https://advent-connect-zw.netlify.app/privacy.html`
into the listing form.

## Updating

The pages are plain HTML + one stylesheet (`style.css`). Edit in
place, commit, push — Netlify re-publishes automatically in
~30 seconds.

When you update the legal copy, bump the "Last updated" date at
the top of the affected page.

## If you pick a different site name

The Edge Functions in `supabase/functions/event-share`,
`job-share`, `product-share`, and `seller-share` each define a
`DOWNLOAD_URL` constant pointing at
`https://advent-connect-zw.netlify.app/download.html`. If you use a
different Netlify site name (or wire up a custom domain), update
that constant in all four files and re-deploy them.

## Custom domain (optional, future)

If you ever buy a domain like `adventconnect.zw`, point it at
Netlify in 3 clicks: Site settings → Domain management → Add custom
domain. Netlify even provisions a free Let's Encrypt SSL cert.
