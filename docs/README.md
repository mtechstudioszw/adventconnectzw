# Advent Connect ZW — public site

Static site that ships the legal pages (Terms / Privacy / Community
Guidelines), an About page, and a Download landing. Served by
**GitHub Pages** straight out of this `docs/` folder so we don't
need a separate hosting bill.

## Enable GitHub Pages (one-time, ~30 seconds)

1. Open
   https://github.com/mtechstudioszw/adventconnectzw/settings/pages
2. **Source:** Deploy from a branch
3. **Branch:** `main`, folder `/docs`
4. Click **Save**
5. GitHub will publish to:
   ```
   https://mtechstudioszw.github.io/adventconnectzw/
   ```
   First build takes ~1 minute. Subsequent pushes that touch
   `docs/` are picked up automatically.

## URLs that result

| Page | URL |
|---|---|
| Home | https://mtechstudioszw.github.io/adventconnectzw/ |
| Terms of Service | …/terms.html |
| Privacy Policy | …/privacy.html |
| Community Guidelines | …/guidelines.html |
| About | …/about.html |
| Download | …/download.html |

The **Privacy Policy URL** is what Google Play Console asks for when
you submit the app for review — paste that link into the Play Store
listing form.

## Updating

The pages are plain HTML + one stylesheet (`style.css`). Edit in
place, commit, push — GitHub Pages re-publishes in ~1 minute.

When you update the legal copy, bump the "Last updated" date at
the top of the affected page (`terms.html`, `privacy.html`,
`guidelines.html`).

## Optional: link share-page fallback to this site

The Edge Functions in `supabase/functions/event-share`,
`job-share`, `product-share`, `seller-share` each define a
`DOWNLOAD_URL` constant. Update those to
`https://mtechstudioszw.github.io/adventconnectzw/download.html`
once the GitHub Pages URL is live — the "Don't have the app? Get
it here" button on every share landing page will then route through
this site instead of the raw GitHub Releases page.
