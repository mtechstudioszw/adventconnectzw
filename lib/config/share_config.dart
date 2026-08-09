import 'app_version.dart';

/// Public Play Store listing for the app. Appended to shared content (Bible
/// verses, etc.) so whoever receives it can install Advent Connect ZW.
String get appDownloadUrl =>
    'https://play.google.com/store/apps/details?id=$kAndroidPackageId';

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
/// Deployed Cloudflare Worker (see cloudflare/share-worker.js). Swap for a
/// custom domain like `https://share.adventconnectzw.com` if one is added.
///
/// **The workers.dev subdomain is part of this URL and it changed on
/// 9 Aug 2026** (`tanatswamichaelmikuwa` → `adventconnectzw`). Renaming a
/// Cloudflare account's subdomain does not leave a redirect behind: the old
/// host stopped resolving entirely, which silently broke every product,
/// event, job and seller link the app had ever shared, including ones
/// already sitting in people's WhatsApp threads. Nothing in the app fails
/// loudly when this is wrong — the links just stop working — so verify the
/// host actually answers before shipping a change to it.
const String kShareBaseUrl =
    'https://advent-share.adventconnectzw.workers.dev';

/// Open Graph share link for a marketplace product.
String productShareUrl(Object id) => '$kShareBaseUrl/product-share?id=$id';

/// Open Graph share link for an event.
String eventShareUrl(Object id) => '$kShareBaseUrl/event-share?id=$id';

/// Open Graph share link for a job listing.
String jobShareUrl(Object id) => '$kShareBaseUrl/job-share?id=$id';

/// Open Graph share link for a seller storefront (keyed by auth_user_id).
String sellerShareUrl(Object authUserId) =>
    '$kShareBaseUrl/seller-share?id=$authUserId';

/// Landing page for a member's friend QR code.
///
/// The QR used to encode the raw `io.supabase.adventconnect://user/<id>`
/// scheme. That works only if the app is already installed — the phone
/// camera of someone who does NOT have it simply does nothing with a scheme
/// no app claims, which is the one case a shared code most needs to handle.
/// This https link opens the app when it is installed and the Play Store
/// when it is not.
///
/// **`/u/<id>`, not `/user-share?id=<id>` like its siblings.** Every
/// character here costs QR density: the payload has to fit in the symbol
/// drawn at a fixed 210dp with a logo punched through the middle, and the
/// query-string form pushed it to 105 bytes — a version-10 symbol at 3.7dp
/// per module. The short path lands at 92, which is version 9 at ~4dp.
/// `friend_qr_test` holds that line.
///
/// Most of what is left is the worker's hostname. A custom short domain
/// (`https://acz.app/u/<id>`) would take this back under 60 and is the real
/// fix if these ever scan badly.
String friendShareUrl(Object userId) => '$kShareBaseUrl/u/$userId';
