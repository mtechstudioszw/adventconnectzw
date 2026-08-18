# NEXT SESSION — start here

**Last session: 18 Aug 2026.** Everything is committed and pushed to
`main` (`bca26dc`). Working tree clean. `flutter analyze` clean (4
pre-existing infos), **624/624 tests pass**.

The laptop was handed to someone else after this session, so local
credentials, `.env` files and Claude Code history were removed on purpose.
See "Restoring this machine" at the bottom.

---

## What shipped

### 1. Rebrand: Advent Connect ZW → **Adventist Super App**

Public branding only. Tagline: **"Connecting SDA people around the globe."**
Splash reads `COMMUNITY • FAITH • WORLDWIDE`. Studio credit is now
**Tanatswa Michael Mikuwa** (MyTech Studios retired in-app).

**NEVER rename these** — they are the app's technical identity:

| Identifier | Value |
|---|---|
| Android applicationId | `io.supabase.adventconnectzw.advent_connect_zw` |
| Dart package | `advent_connect_zw` |
| Deep-link scheme | `io.supabase.adventconnect://` |
| FCM default channel | `advent_connect_zw_default` |
| Share worker | `advent-share.adventconnectzw.workers.dev` |
| Legal URLs | `mtechstudioszw.github.io/adventconnect-legal/` |
| Support inbox | `adventconnectzw@gmail.com` |

### 2. Brand assets

`assets/icon/logo.png` is now a real transparent PNG (2 MB → 122 KB),
recovered from the founder's JPEG by un-premultiplying the white-on-black
mask. Plus `app_icon_foreground.png` (adaptive) and `app_icon.png` (square,
on the sampled brand blue `#022171`). Regenerate with
`scripts/build_brand_assets.ps1`; sources in `design/brand/`.

### 3. Country support (`database/patch_213_global_country.sql`)

ISO-3166 alpha-2 codes on `profiles`, `churches`, `events`, `jobs`,
`products`, `sellers`, all backfilled `'ZW'`. `jobs.province` is no longer
NOT NULL. Collected in onboarding step 1 (auto-detected from device
locale), editable in Edit profile, shown with a flag on profiles, products
and seller storefronts. Data lives in `lib/config/countries.dart`; the
picker is `lib/widgets/country_picker_sheet.dart`.

### 4. Sabbath sundown was ~2 HOURS WRONG since launch

Not a rebrand regression — it shipped from day one, in Zimbabwe too. `n`
(days since J2000) must be a **whole number**; the code fed it a `-0.0825`
day fraction. Fixed, plus sundown is now a UTC instant rendered via
`toLocal()` (so DST works), location resolves ZW province → country
centroid → Harare, and the duplicate copy of the equation in
`sabbath_timer_screen.dart` is deleted. Pinned by 11 tests against London
(20:21Z) and Harare (15:47Z).

---

## ⚠️ DO THIS FIRST next session

1. **Run `database/patch_213_global_country.sql` on Supabase.** Nothing
   about country persists until this is applied. Verify with the queries
   in the comment block at the bottom of that file — especially the
   column-privileges one.

2. **Listing forms have no country input yet.** `add_product_screen`,
   `post_job_screen`, seller signup and `suggest_church_screen` all still
   force a *Zimbabwean province* dropdown, and the DB column defaults to
   `'ZW'` — so a Kenyan seller's listing is silently tagged Zimbabwe.
   **This is actively creating bad data.** Plan: add `CountryField` above
   the province dropdown, defaulted from `AuthService.currentCountry()`;
   keep the province dropdown only when the country is `ZW`, otherwise a
   free-text region field.

---

## Then, in rough priority order

**Country, remaining**
- Feed: country-first with a "Worldwide" toggle (decided, not built).
- Marketplace / Jobs: country *filtering* (display is done, filtering is not).
- Church directory + events country UI; member-directory country filter.

**Other global gaps found but untouched**
- WhatsApp handoff hardcodes **+263** — a non-Zimbabwean seller's number
  will not open. `Country.dialCode` is already available.
- `profiles.language_preference` is CHECK-constrained to
  `english|shona|ndebele` — a hard blocker for global. Shona-first stays
  for ZW.
- Currency on listings; division/union grouping (`churches.conference`
  already exists).

**Global church directory**
- **Do NOT scrape `adventistdirectory.org`** — its robots.txt names
  `ClaudeBot: Disallow: /` and every `adventist.org` host 403s.
- Use the official **Adventist OrgMast Data API** (ASTR);
  the founder must request access.
- Scale: **106,936 churches + 78,061 companies** worldwide vs ~2,600 ZW
  rows today. `ChurchService.fetchChurches(limit: 5000)` truncates and the
  onboarding church picker filters **in memory** — both must go
  server-side and paginated *before* any import.

---

## Not deployed yet (code is done, production is not)

1. **Supabase edge functions** — `notify-fcm` + the four `*-share`
   functions. Until redeployed, push titles and shared-link cards still say
   "Advent Connect ZW".
2. **Cloudflare** `share-worker.js`.
3. **Email logo** — auth templates load
   `…/storage/v1/object/public/library/branding/logo-240.png`, which still
   holds the OLD mark.
4. **Play Console** — listing copy is in `docs/PLAY_STORE_LISTING.md`.
   Rename the subscription's *display title* only, never the product ID.
   **Countries/regions is probably still Zimbabwe-only — that setting, not
   the rebrand, is what makes the app available worldwide.**
5. `dart run flutter_launcher_icons` to regenerate launcher icons.

---

## Testing the build

Every push to `main` builds a debug APK via
`.github/workflows/build-apk.yml` and publishes it to the `latest-debug`
release: <https://github.com/mtechstudioszw/adventconnectzw/releases> →
`adventist-super-app-debug.apk`. Settings → App version shows the commit
SHA, so you can confirm you are not chasing bugs in a stale build.

---

## Restoring this machine

The repo is safe on GitHub; the laptop was sanitised. To resume:

1. `git clone https://github.com/mtechstudioszw/adventconnectzw.git`
2. Restore from the backup folder (see `RESTORE_README.md` inside it):
   `android/key.properties` + the release keystore, `admin/.env.local`,
   Claude Code sessions/history, and git identity.
3. `gh auth login` (or re-add an SSH key), then `flutter pub get`.
4. Secrets were never put in the backup in plaintext — transfer them from
   your own drive/password manager.
