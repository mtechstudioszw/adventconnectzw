/// Base URL that serves the Open Graph share / landing pages for shared
/// products, events, jobs and sellers.
///
/// WHY NOT SUPABASE: the *-share Edge Functions on the default
/// `*.supabase.co` / `*.functions.supabase.co` domain are forced to
/// `Content-Type: text/plain` + a CSP sandbox by Supabase's platform
/// security. That stops WhatsApp/Facebook crawlers reading the OG tags (no
/// thumbnail) AND stops the in-page redirect from opening the app. So the
/// pages are served from a Cloudflare Worker that returns real `text/html`
/// (see `cloudflare/share-worker.js`).
///
/// TODO(deploy): set this to your deployed Worker route, e.g.
///   'https://share.adventconnectzw.com'  (custom domain), or
///   'https://advent-share.<your-account>.workers.dev'.
/// Until then sharing falls back to the (thumbnail-less) plain-text page.
const String kShareBaseUrl = 'https://advent-share.REPLACE_ME.workers.dev';

/// Open Graph share link for a marketplace product.
String productShareUrl(Object id) => '$kShareBaseUrl/product-share?id=$id';

/// Open Graph share link for an event.
String eventShareUrl(Object id) => '$kShareBaseUrl/event-share?id=$id';

/// Open Graph share link for a job listing.
String jobShareUrl(Object id) => '$kShareBaseUrl/job-share?id=$id';

/// Open Graph share link for a seller storefront (keyed by auth_user_id).
String sellerShareUrl(Object authUserId) =>
    '$kShareBaseUrl/seller-share?id=$authUserId';
