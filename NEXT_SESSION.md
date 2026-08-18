# NEXT SESSION — start here

**Last session: 18 Aug 2026 (second sitting).** Both blockers from the
previous handoff are **done**, plus eleven issues the founder reported off
the last debug build.

`dart analyze lib test` → **4 pre-existing infos, exit 0** (the documented
baseline; nothing new).

---

## Database patches applied THIS session

All applied to project `adventconnectzw` (ref `eqbyvasteolqyktbqbem`) via the
Supabase Management API and verified by reading the output, not by assuming
"it ran".

| Patch | What |
|---|---|
| **213** (existing, never run) | country on profiles/churches/events/jobs/products/sellers |
| **214** (new) | country on `church_suggestions` — 213 missed it |
| **215** (new) | church cooldown 90d → **14d**; same 14d gate on `country` |
| **216** (new) | birthday notifications: once per day, from 08:00 local |
| **217** (new) | `products.price_currency`: ISO 4217 **shape** check, not a 3-value list |

### patch_213 was the cause of three "app bugs"

It had never been run, and three separate bug reports were all this one
missing column:

| Reported as | Actually |
|---|---|
| Onboarding country step: "Could not update profile" | `updateProfile` upserted `country`; its retry only strips `cover_photo_url`, so it threw again into the generic catch |
| Profiles don't load | `user_profile_service.dart` selects an explicit column list including `country` — PostgREST 400s the **whole** query on a missing column |
| Seller profiles don't load | Same query inside a `Future.wait` in `seller_profile_screen.dart`; one rejection took the whole page down |

No Dart changes were needed for any of them. **When several unrelated
screens break at once, query `information_schema.columns` before reading
Dart.**

---

## Country / global readiness

**Country pickers on five listing forms** — the four named in the last
handoff plus **Edit store**, which is the only way an existing seller can
correct the `'ZW'` the backfill gave them: `add_product_screen`,
`post_job_screen`, `setup_store_screen`, `edit_store_screen`,
`suggest_church_screen`.

New `CountryFormField` (in `lib/widgets/country_picker_sheet.dart`) renders
the picker inside **the caller's own `InputDecoration`**, because each post
form builds inputs from a different local decoration helper and the existing
`CountryField` paints its own box.

Pattern in all five: country defaults from `AuthService.currentCountry()` (or
the row being edited); the **Zimbabwean province dropdown appears only when
country is `ZW`**, otherwise the same `province` column takes free-text
"State or region". Province stays mandatory in ZW only.

**Watch the asymmetry in the update paths:** `'country': ?country` but
`if (country != null) 'province': province`. Province is written *even when
null*, so switching a listing to Kenya clears the stale Zimbabwean province —
`?province` would skip the null and strand it.

**WhatsApp handoff no longer assumes Zimbabwe.** Every handoff did
`raw.replaceAll(RegExp(r'\D'), '')` and handed that to `wa.me`, so a seller
who typed `0778 092 494` produced `wa.me/0778092494` — an error page. Never a
ZW-only bug, but unfixable without a country. Now
`Countries.toWhatsAppDigits(raw, countryCode:)` normalises against the
**seller's** country (`+`/`00` respected, trunk `0` swapped for the dial
code, no guessing when the country is unknown). `MarketOrder` gained
`sellerCountry` so the order handoff has it too. Phone-field hints come from
`Countries.phoneHint(country)` instead of a hard-coded `+263`.

**Language switcher removed from Settings.** It offered English / Shona /
Ndebele and changed nothing — no translations exist, so it persisted a
preference no screen read, and it promised something the app cannot do now
that non-Zimbabweans are signing up. The Bible-translation, Sabbath-School
(~90 languages) and Hymnal pickers are separate and untouched. This also
sidesteps the `profiles.language_preference` CHECK constraint that was
flagged as a global blocker.

---

## Other fixes this session

1. **App icon** — `flutter_launcher_icons` had never been run after the
   rebrand: `colors.xml` still carried the old `#0D1B3E` adaptive background
   against pubspec's `#022171`. Regenerated. Separately, the native
   `launch_background` (the frame *before* the Flutter splash) was dark navy
   while the splash paints light grey, so every cold start flashed navy then
   snapped light — now `#F5F7FA`, with a new `values-night/colors.xml` at
   `#0B1124`.
2. **Splash line** — "TANATSWA MICHAEL MIKUWA" → "Connecting Adventists all
   over the world". ⚠️ Differs from the tagline recorded last session
   ("Connecting SDA people around the globe"); founder dictated the new
   wording. Make `docs/` agree with whichever wins.
3. **Shared links opened "Route not found".** The Android manifest had no
   `flutter_deeplinking_enabled`, so the engine handed go_router the raw
   `io.supabase.adventconnect://seller/<id>` *while* `app_links` handed the
   same link to `DeepLinkService`. go_router cannot match a URI whose type is
   in the HOST, so its error page won the race. Manifest now sets it
   `false` (verified safe: `supabase_flutter` catches `login-callback`
   through app_links, not the Router), plus `_shareLinkRedirect` in
   `router_config.dart` as a belt-and-braces net for iOS.
4. **Encryption notice was overclaiming.** It said "your messages are
   end-to-end encrypted, nobody outside this chat can read them" while
   `sendMessage` encrypts **only the body of a text message** — photos and
   voice notes are storage paths the server can read. Reworded in
   `chat_screen.dart` and `chat_contact_sheet.dart`.
5. **Chat privacy is GLOBAL, not per-chat** — all four settings are
   `profiles` columns. Opening it from inside a conversation made it read as
   per-person; the screen now says so.
6. **Security code in the mini profile** — new `E2eeService.securityCode()`,
   Signal's 60-digit numeric fingerprint (`NumericFingerprintGenerator`,
   5200 iterations) over both identity keys, with the encryption note and a
   "Learn more" into the privacy policy. Pinned by
   `test/security_code_symmetry_test.dart`, which proves both handsets derive
   the same digits from swapped arguments.
7. **Tapping a chat photo exited the viewer** — `full_image_viewer.dart`
   wrapped its whole body in a dismissing `GestureDetector`. Tap is now
   inert; ✕ and system back dismiss.
8. **"Save to gallery" saved only the first photo** of an album and still
   reported success. Now saves every photo, asks for permission once, and
   reports partial results honestly ("3 of 5 saved"). Menu says "Save all N
   photos".
9. **Home + Profile show the home church NAME**, not a count. "1 Churches"
   was always 1 or 0 and told the member nothing.
10. **Devotion card slide order** now matches the Home pill row exactly:
    Bible, Quiz, EGW, Sabbath School, Hymn, Music. The pills were already in
    that order — only the slides were out of step. Note `LibraryTiles` pills
    carry their own tab indexes on purpose; do NOT "tidy" them to match the
    Library TabBar, whose order is deliberately different.
11. **Birthday notifications** — see patch_216. They fired at **midnight
    local** (the 22:00-UTC tick starts the Harare day) and then a **second
    time ~20h later**, which is the "5pm, birthday nearly over" copy the
    founder saw. Now day-scoped and held until 08:00 local.

---

## ⚠️ DO THIS FIRST next session

1. **`app_config.e2ee_enabled` is `0`.** Encryption ships dark on purpose
   (see `E2eeService._enabled`), which means **items 4 and 6 above are
   invisible in the running app** — both are gated on `isEncryptionOn`. Flip
   to `1` **only after sending and receiving on two real handsets**; anything
   sent while it is wrongly on is unreadable forever.
2. **Sabbath timer already handles other countries** — `_coords()` resolves
   ZW province → the member's country centroid (`countries.dart`) → Harare.
   Nothing to do; it just needs a build newer than the founder's current APK.
3. **Nothing promotes a church suggestion into `churches`** — no SQL
   function, no admin-web code; it is done by hand. Whoever does it must copy
   `country` across or the `'ZW'` default silently wins and patch_214 buys
   nothing.

---

## Open, decided but not built

**Donations outside Zimbabwe** — the founder asked for options beyond
EcoCash. The blocker is not the app, it is that **Zimbabwe cannot receive on
PayPal or Stripe** (send-only), so the usual "add a PayPal link" answer does
not work. Realistic rails, cheapest first, all of which keep DonateScreen's
current design (show details, collect nothing in-app):
  - **Remittance to the existing EcoCash line** — Mukuru, WorldRemit,
    Western Union, Remitly all serve the ZW corridor. Zero integration; the
    receiving side already exists.
  - **A USD nostro bank account** (SWIFT) for larger gifts.
  - **Payoneer**, which does support ZW receiving in some cases.
  - **USDT (TRC-20)** — widely used by the Zimbabwean diaspora; check Play
    policy before shipping.
  - PayPal **only** via a trusted non-ZW account, which has its own risks.
  Suggested build: make DonateScreen country-aware off
  `AuthService.currentCountry()` — ZW sees EcoCash, everyone else sees the
  remittance instructions. Founder must first say which accounts exist.

---

## Ambient background — BUILT this session

The splash's drifting particle field now sits behind the whole app.
`lib/widgets/ambient_background.dart` paints the opaque ground plus
`AmbientPainter`, and is installed once in `MaterialApp.builder` so it lives
under the router's Navigator — pages slide over a field that stays put.

**91 Scaffold backgrounds across 83 files became `Colors.transparent`.** Read
this before touching any of them:

- Only the **Scaffold** background changed. `palette.scaffoldBg` itself is
  untouched, because headers rely on it to occlude content scrolling under
  them (CLAUDE.md's flat-header rule). The two non-Scaffold uses — a modal
  sheet in `conversations_screen` and the `watch_screen` header — were
  deliberately left opaque.
- **Five screens keep an opaque Scaffold on purpose** because they already
  paint this same field themselves: `auth_shell`, `onboarding_flow_screen`,
  `onboarding_screen`, `maintenance_screen`, and `chat_screen` (via
  `ChatWallpaper`). Making those transparent stacks two fields.
- **It runs at ~15fps, not 60** (`AmbientBackground.frameInterval`), behind a
  `RepaintBoundary`, and freezes entirely under "reduce motion".
  `ChatWallpaper`'s own doc comment explains why: a full-screen animated
  CustomPaint under a flung list repaints the viewport every frame, and this
  one is under *every* screen for the whole session. The drift is a 14s loop
  of soft blobs, so 15fps is indistinguishable from 60 at a quarter the cost.
  **This is the one change that could not be verified without a real
  handset** — if scrolling feels worse on a mid-range phone, raise
  `frameInterval` or pin the field static like `ChatWallpaper` does.

---

## Then, in rough priority order

**Country, remaining**
- Feed: country-first with a "Worldwide" toggle (decided, not built).
- Marketplace / Jobs: country *filtering* (capture + display are done now).
- Church directory + events country UI; member-directory country filter.
- Every posting form now captures country — `post_event_screen` was the last
  one and got its picker this session, so nothing is defaulting to `'ZW'`
  silently any more.

**Currency — done, with one gap**

`products_price_currency_check` hard-coded `ARRAY['USD','ZWL','ZAR']`, so a
Kenyan seller could not price in KES: the insert failed on a constraint
violation the app could not explain. patch_217 replaces it with a *shape*
check (`~ '^[A-Z]{3}$'`), the same reasoning patch_213 used for country —
the database rejects junk, the app curates the list. `orders` and
`order_items` carry no currency CHECK at all, so they inherit this for free,
and `formatMoney` already renders any code (`USD → $`, else `KES 500`).

`Countries.currencyChoices(country)` now drives the dropdown: Zimbabwe keeps
USD/ZWL/ZAR, everyone else gets their own currency then USD. The map behind
it (`Countries.currencyOf`) covers Africa thoroughly and the main diaspora
destinations, and **returns null rather than guessing** — an unknown country
is offered USD alone, because a wrong currency on a real listing is acted on
by a buyer. Adding a country is a one-line fix.

- **The gap:** only `add_product_screen` offers the choice. Nothing converts
  between currencies and nothing filters by them, so a buyer browsing sees
  mixed currencies side by side in the grid. That is honest but not pretty,
  and is the next thing to look at once country *filtering* lands.

**Other global gaps**
- `notify_birthdays()` still uses `Africa/Harare` as everyone's clock; a real
  fix needs a per-member timezone, which `profiles.country` alone cannot give
  (the US spans six).
- Division/union grouping (`churches.conference` already exists).

**Global church directory**
- **Do NOT scrape `adventistdirectory.org`** — robots.txt names
  `ClaudeBot: Disallow: /` and every `adventist.org` host 403s.
- Use the official **Adventist OrgMast Data API** (ASTR); the founder must
  request access.
- Scale: **106,936 churches + 78,061 companies** worldwide vs ~2,600 ZW rows
  today. `ChurchService.fetchChurches(limit: 5000)` truncates and the
  onboarding church picker filters **in memory** — both must go server-side
  and paginated *before* any import.

---

## Not deployed yet (code is done, production is not)

1. **Supabase edge functions** — `notify-fcm` + the four `*-share`
   functions. Until redeployed, push titles and shared-link cards still say
   "Advent Connect ZW".
2. **Cloudflare** `share-worker.js`.
3. **Email logo** — auth templates load
   `…/storage/v1/object/public/library/branding/logo-240.png`, still the OLD
   mark.
4. **Play Console** — listing copy in `docs/PLAY_STORE_LISTING.md`. Rename
   the subscription's *display title* only, never the product ID.
   **Countries/regions is probably still Zimbabwe-only — that setting, not
   the rebrand, is what makes the app available worldwide.**

---

## NEVER rename these — the app's technical identity

| Identifier | Value |
|---|---|
| Android applicationId | `io.supabase.adventconnectzw.advent_connect_zw` |
| Dart package | `advent_connect_zw` |
| Deep-link scheme | `io.supabase.adventconnect://` |
| FCM default channel | `advent_connect_zw_default` |
| Share worker | `advent-share.adventconnectzw.workers.dev` |
| Legal URLs | `mtechstudioszw.github.io/adventconnect-legal/` |
| Support inbox | `adventconnectzw@gmail.com` |

---

## Working on this machine

- **`flutter analyze` deadlocks** against the VS Code Dart extension's
  analysis server here — it sat 25 minutes at "Analyzing…" on ~5s of CPU.
  Use **`dart analyze lib test`**. Baseline is **4 infos**
  (2× `event_details_screen`, `push_service`, `date_format`), exit 0.
- On a fresh clone the whole `lib/` folder shows red until `flutter pub get`
  finishes. That is not a code problem.
- Git on Windows rewrites line endings: `ic_launcher.xml`, the iOS
  `project.pbxproj` and the desktop `generated_plugin_registrant` files show
  as modified with **empty diffs**. `git checkout --` them before committing.
- Applying a patch without the dashboard: `POST
  https://api.supabase.com/v1/projects/{ref}/database/query` with a `sbp_`
  token. **Send the body as UTF-8 bytes** — PowerShell's default encoding
  mangles the em-dashes in these files and the API 400s with a JSON parse
  error at ~position 113.
- Every push to `main` builds a debug APK via
  `.github/workflows/build-apk.yml` → the `latest-debug` release →
  `adventist-super-app-debug.apk`. Settings → App version shows the commit
  SHA, so you can confirm you are not chasing bugs in a stale build.
