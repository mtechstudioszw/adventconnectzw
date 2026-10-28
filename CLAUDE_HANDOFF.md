# CLAUDE_HANDOFF — Advent Connect ZW (Adventist Super App)

Handover from the local Windows session (27–28 Oct 2026) to Claude Code Cloud.
Read this file, then `CLAUDE.md`, then the master prompt, before touching code.

---

## 1. Where the instructions live

| File | What it is |
|---|---|
| `adventist_super_app_complete_13_batch_prompt-1.txt` | **The owner's master prompt.** Full scope, the 13 batches, acceptance criteria and working rules. It is the source of truth for what to build and in what order. |
| `CLAUDE.md` | Design + technical rules that predate this work (colours, Poppins, flat headers, transparent scaffolds, `profiles` grant checklist, `pref:` cache keys). Still binding. |
| `docs/BATCH_1_AUDIT.md` | The Batch 1 audit: baseline, every fix with root cause, open findings by severity. |
| This file | State of play and the exact resume point. |

### Non-negotiable working rules (from the master prompt)
1. Audit → fix bugs → then build. Never rewrite working systems.
2. **Stop and ask** before any change that conflicts with existing routes,
   navigation, schema, auth, permissions or established behaviour. Give the
   conflict, options, a recommendation, impact and risks, then wait.
3. Work in the 13 batches, one at a time. Report at the end of each.
4. Never fake data or functionality. Respect content licences.
5. Never commit secrets.

### Batch order (from the master prompt file — note it differs from an
earlier chat version; the FILE wins)
1. Audit, bug fixes, Advent AI cleanup — **DONE**
2. Core app shell, Home, Marketplace, Profile — **IN PROGRESS**
3. Library information architecture & design
4. Bible app experience
5. Sabbath School experience & date bug
6. Hymnal (multilingual)
7. Ellen G. White library & reading tools
8. Music player, audio & Android system media controls
9. Search, speed, autocomplete & profile image quality
10. Watch tab
11. Settings
12. Profile onboarding, country rules & profile quality
13. Quizzes, spiritual growth, final QA & release readiness

---

## 2. Architecture (what exists)

- **Flutter 3.41.9 / Dart 3.11.5** (pubspec `sdk: ^3.11.3`). 400+ Dart files
  under `lib/`, ~90 test files under `test/`.
- **Backend:** Supabase (auth, Postgres with RLS + triggers, storage, edge
  functions in `supabase/functions/`). Region Africa (Cape Town) — never change.
  SQL migrations are hand-run patches in `database/patch_NNN_*.sql`
  (latest: `patch_269`).
- **Firebase:** FCM push, Crashlytics, Analytics only. `firebase_auth` is
  permanently excluded — Supabase does auth.
- **Routing:** go_router 14.8.1, `lib/config/router_config.dart`.
  - **NEW (Batch 2):** the five tabs — Home, Watch, Chat (`/messages`),
    Marketplace, Profile — are a `StatefulShellRoute.indexedStack` rendered by
    `lib/screens/widgets/tab_shell.dart`. Tabs stay alive when you switch.
  - Every **direct child route of a tab** carries
    `parentNavigatorKey: rootNavigatorKey` so it still opens full-screen above
    the island. A new child route without it will open inside the tab.
  - Never `push` a tab route (it duplicates the shell navigator). Use
    `goNamed`. For Chat → Requests use `ConversationsScreen.openRequests(router)`.
  - All other routes are flat top-level `GoRoute`s.
- **State:** services with static `ValueNotifier`s + `StatefulWidget`s. No
  Provider/Bloc/Riverpod — do not introduce one.
- **Cache/offline:** Hive via `CacheService` (keys starting `pref:` survive
  sign-out; everything else is user-scoped and cleared).
  `cached_network_image` with `adventImageCacheManager`.
- **Global overlays** live in `MaterialApp.builder` (`lib/main.dart`):
  ambient background, voice-note bar, docked music/video (`GlobalMediaBars`).
  The Advent AI floating bubble was **removed** in Batch 1.
- **Audio:** `just_audio` + `just_audio_background` (audio_service 0.18.18) in
  `MusicPlayerService`; `audioplayers` for chat voice notes.
- **Video:** `youtube_player_iframe`.
- **Ads/Premium:** Appodeal, `in_app_purchase`. Payments are hidden on iOS
  (`kHidePayments`).

### Builds / CI (no Mac — iOS builds in the cloud)
- `.github/workflows/`: `analyze.yml`, `build-apk.yml`, `build-aab.yml`,
  `ios-build.yml`.
- **iOS signing comes from GitHub Secrets** (`APPLE_CERTIFICATE_P12_BASE64`,
  `APPLE_PROVISIONING_PROFILE_BASE64`, `APP_STORE_CONNECT_API_*`, …), decoded
  at build time. Nothing in the repo is needed for signing.
- Android release signing also comes from secrets (`ANDROID_KEYSTORE_*`).
- Local commands: `flutter pub get`, `flutter analyze`, `flutter test`.
  On the old Windows PC a full analyze took ~35 min; `dart analyze <files>`
  on just the changed files is much faster.

---

## 3. Batch 1 — DONE (commit `dcbcc8a`)

Verified: changed files `dart analyze` → **No issues found**; 32 targeted tests
passed. Full `flutter analyze` baseline was 0 errors, 0 warnings, 3 infos.

| Fix | Root cause | Key files |
|---|---|---|
| Advent AI floated over chats opened from Profile → Chat (and on Library, Settings, Home…) | App-wide bubble hid itself by reading `currentConfiguration.uri.path`, which `push` never updates | Bubble deleted; only entry point is the Chat inbox button (`conversations_screen.dart`). `test/advent_ai_placement_test.dart` |
| Sabbath School chip ≠ content | `weekday % 7` into a Sabbath-first list shifted every label one day; Friday supplements shown as weekday chips | `lib/models/sabbath_school_model.dart` (`chipLabel`, `isDailyReading`, `ssWeekdayShort`), `ss_lesson_screen.dart`. `test/ss_day_labels_test.dart` |
| Android music missing from system media controls | `MainActivity` wasn't audio_service's activity → init threw → silent fallback | `MainActivity : AudioServiceFragmentActivity()` (still a FragmentActivity, biometrics OK). **Needs on-device check.** |
| Country "rejected but switched" | Metadata written before the trigger-guarded `profiles` row | `auth_service.dart` writes the row first; `edit_profile_screen.dart` re-reads after a failed save |
| Search stale results | Overlapping searches; last response won | `search_screen.dart` drops responses whose query ≠ `_lastQuery` |
| Blurry search avatars | Stored Google `=s96-c` URL used raw | `search_screen.dart` uses `photoUrlAtSize(…, 132)` |
| Committed Apple signing material | — | Untracked + `.gitignore`d (`*.p8`, `*.pem`, `*.cer`, etc.) |

---

## 4. Batch 2 — IN PROGRESS (this push)

Owner decisions taken in this session:
- **Tabs stay alive** → `StatefulShellRoute` + `TabShell` (approved).
- **The floating island stays exactly as designed** — it is drawn once by
  `TabShell` instead of by each tab screen. Do not remove or restyle it.
- **Devotion / Verse of the Day card keeps opening the Library Bible tab**
  (founder decision of 4 Aug 2026 reconfirmed).
- **Home order (owner, 27 Oct 2026):**
  header → live quiz strip / live banner (+ urgent banner, fundraiser when
  present) → **Churches · Events · Prayer** chips → **Stories** →
  **Today cards** (devotion, Sabbath School, hymn…) → **Library chips**
  (Bible, Quiz, EGW, Sabbath, Hymnal, Music) → Featured church events → feed.
- **Composer card removed from the column**; posting is a **floating gold "+"**
  (`HomeComposeFab`) that opens the same create sheet. Navy glyph on gold for
  contrast. Gold is Home's one gold accent now.
- **Donate chip replaced by Prayer** (shows on iOS too since it asks for no money).
  Donate is still reachable from its route `/donate` (check that Profile/Settings
  still link to it — not yet verified).
- **Featured church events stay just before the feed.**

### Done and verified
- `TabShell` + `StatefulShellRoute`, island/badges/hide-on-scroll/Marketplace
  banner moved into the shell, Home re-tap scroll-to-top via
  `TabShell.registerReselect`, friend-request badge via
  `TabShell.pendingFriendRequests`, `ConversationsScreen.openRequests`.
  `dart analyze` on all those files → No issues; 28 tests passed
  (`tab_shell_test`, `bottom_nav_test`, `ads_never_in_chat_test`,
  `advent_ai_placement_test`, `ad_banner_height_test`, `hide_on_scroll_test`,
  `home_shortcut_chips_test` (old version), `widget_test`).

### Verified in the cloud session (28 Oct 2026)
- Home composer removal, `HomeComposeFab`, Donate → Prayer:
  `dart analyze` clean; `home_shortcut_chips_test`, `tab_shell_test`,
  `bottom_nav_test` pass.
- `ComposerEntry` was unused after the composer left Home — **deleted**
  (`HomeComposeFab` and `HomeShortcutChips` stay in `composer_entry.dart`).
- **Sabbath School Today card now opens today's reading.**
  `LibraryLaunchIntent.openToday` (set with `quarterlyId` by `_LessonPage`);
  `SabbathSchoolTab._consumeLaunchIntent` pushes the lesson list, then
  `_openTodayOver` finds the current week whose days contain today
  (`ssTodayIndex` in `sabbath_school_model.dart`) and pushes
  `SsDayReaderScreen` on top. Back: day → quarter → shelf. No reading today
  (offline, nothing cached, between quarters) → stays on the list. If the
  member leaves the list before the lookup resolves, nothing is pushed.
  Card hint now reads "Open today's lesson". Test: `test/ss_today_index_test.dart`.
- **Still to check on a device:** the gold FAB sits above the island and
  doesn't cover the last feed card; the Today-card → reader flow end to end.

- **Home feed error states (Home polish, part 1).**
  - First page failed + nothing cached used to show the day-one card
    "Your feed starts here — follow a church", i.e. told an offline member
    they had no friends. Now `_feedFailed` → `FeedErrorCard`
    (`lib/widgets/home/feed_error_card.dart`): "You're offline" vs
    "Couldn't load your feed", with Try again. Test: `test/feed_error_card_test.dart`.
  - "Load more" failure was silent, left an 80px blank, and the scroll
    listener refired the request on every scroll event near the bottom.
    Now `_loadMoreFailed` stops auto-paging and the footer shows Try again.
  - Not unit-tested in place: `HomeScreen` has no test harness (needs
    Supabase). Check on a device in airplane mode on a fresh install.
- Donate is still reachable: Settings → `_openDonation` (Android only, `kHidePayments`).

- **Featured church events (Home polish, part 2).** It fetched once in
  `initState`, and with Home now a kept-alive tab that meant once per
  session: new church events never showed and pull-to-refresh skipped it.
  Now: paints the cached list on the first frame (offline too, past events
  dropped), refetches on `refreshTick` (bumped by Home's `_refresh()` —
  pull-to-refresh, "Updated" strip, feed Try again). The fetch throws instead
  of returning `[]`, so a dead connection can't wipe the cache.
  `Event.toJson` now writes the `churches` / `profiles` joins (only caches
  use it) — cached events kept their church name and logo. Test:
  `test/event_cache_roundtrip_test.dart`.
- Decided **against** a loading skeleton for Featured church events: most
  days there are none, so a reserved block would appear then collapse —
  a jump in the other direction. The cache solves the pop-in instead.
- Full `flutter test`: **769 passed** (28 Oct 2026, cloud).

- **Marketplace audit, part 1 (fixed):**
  - Category/scope responses raced: flick Books → Clothing and the slower
    Books answer could land last under the Clothing chip. `_loadGen` drops
    stale responses.
  - Switching category kept the OLD grid up while loading, and if the load
    failed it stayed up forever with no error (error only showed over an
    empty grid). A filter change now clears the grid (skeleton → result or
    error); back on "All" offline falls back to the cached grid.
  - A failed pull-to-refresh over a showing grid was silent → offline toast
    or "Couldn't refresh products."
  - **Search with a comma or bracket broke the query** in Marketplace,
    Churches (x2), Directory, Events and Jobs — the raw term was pasted into
    PostgREST `or()` syntax. New `lib/utils/postgrest_filter.dart`
    `orFilterValue()` quotes it. Test: `test/or_filter_value_test.dart`.
  - Full `flutter test`: 771 passed.
  - **Correction to the above (found by the new widget test):** clearing
    the grid on a filter change put the WHOLE screen back into the
    skeleton (`ContentReveal`), hiding the category chips while a category
    loaded. Now only the first load skeletons the screen (`_firstLoad`);
    later loads skeleton the grid (`ShimmerLoaders.productGridSliver`).
    Test: `test/marketplace_category_race_test.dart` (fails on the original
    code, passes now).
  - Header title block overflowed by 0.2px (line boxes round up) → 2px slack.
- **Product details (fixed):** shared link to a deleted listing crashed
  (`_product!`); now "This listing is no longer available" with a back
  button, and a stale grid item that's gone loses its buy actions. Seller-
  removed listings no longer open for buyers as "RESERVED". Offline save
  no longer says "Sign in". Test: `test/product_details_gone_test.dart`.
- **New test harness:** `test/helpers/fake_supabase.dart` — real Supabase
  client, HTTP answered by an in-test handler. Use it to widget-test
  screens that read through the static services. Wait with
  `t.runAsync(() => Future.delayed(...))` + `pump`; a failed request
  leaves postgrest retry timers, so pump ~30s before the test ends.
- Full `flutter test`: **776 passed**.
- **Edit listing (fixed):** subcategory, condition and location were never
  pre-filled in edit mode and never sent by `SellerService.updateProduct`
  — "Like new" opened as "New" and every change to those three was
  silently dropped. Prefilled now; `updateProduct` takes them (null =
  unchanged, '' clears; an unknown legacy condition is left alone and the
  dropdown shows its hint instead of crashing).
- **Daily post limit message was never shown, anywhere.** `PostLimitError`
  builds "You've listed 3 products today. Try again in 24 hours." but all
  seven create screens (product, news, post, story, prayer, event, job)
  caught it with `catch (_)` → "Please try again". New
  `PostLimitError.messageFor(e, fallback:)` (limit → its message; offline →
  offline; else fallback) used in all seven.
- `signInFake(userId)` added to the test harness.
  Test: `test/edit_product_fields_test.dart`. Full suite: **780 passed**.
- **Marketplace findings NOT fixed (need a decision):**
  - `fetchProducts` sends every approved seller id in the URL
    (`inFilter('seller_id', …)`). Fine now; at a few hundred sellers the
    URL gets long enough to fail. Proper fix is server-side (a view or RLS
    join) = schema change → owner approval.
  - `CategoryScreen` (`/marketplace/categories`) is unreachable — nothing
    links to it — and it ignores the country scope. Remove or relink.

### Resume point (exact)
**Batch 2 → Marketplace audit, part 2 (continued):** seller profile,
add/edit product flow, listing card hierarchy. Then Profile.
- **Done:** Home left open overnight kept yesterday's devotion and
  hymn/track/book. Home now has an `AppLifecycleListener`; on resume, if the
  UTC day changed (devotion RPC and TodayCard picks both roll on UTC), it
  runs `_refresh()`, which also refetches the devotion and bumps
  `TodayCard.refreshTick`. Pull-to-refresh refreshes them too now.
  Not unit-tested (Home/TodayCard need Supabase) — check on device.

Then, still Batch 2:
1. Home polish: card visual pass (states done)
   (keep CLAUDE.md colours, Poppins, flat headers, transparent scaffolds).
2. Marketplace audit + redesign (listing cards, categories, search/filters,
   empty/loading states). No new checkout/payment features without approval.
3. Profile redesign (layout, identity, avatar quality, actions). Profile →
   Chat must open the normal conversation (already fixed — keep it so).
4. End-of-batch report + full `flutter analyze` + full `flutter test`.

---

## 5. Pending owner actions

1. **Run `database/patch_269_country_metadata_resync.sql`** in Supabase
   (preview query first). Repairs members whose auth metadata kept a
   country the cooldown rejected.
2. **Rotate the App Store Connect API key `5DP8YVY728`** if the repo is or was
   public — it is still in git history (old commits). New key → update the
   `APP_STORE_CONNECT_API_*` secrets. Distribution cert rotation optional if
   the repo is private. Do NOT rewrite git history without the owner's say-so.
3. **On-device Android test** of music: notification, lock screen, Bluetooth
   buttons, and that the biometric prompt still appears.
4. Back up the local signing files (still on the old PC, untracked) somewhere
   safe outside the repo.

---

## 6. Known open issues (by batch)

| Sev | Issue | Batch |
|---|---|---|
| HIGH | Onboarding pre-selects country from device locale (`onboarding_flow_screen.dart:63`, `Countries.detect()`); must be an explicit choice | 12 |
| MEDIUM | ~20 avatar renders bypass `photoUrlAtSize` (seller, blocked users, directory, edit profile, onboarding…) | 9 |
| MEDIUM | `GlobalMediaBars` and checks in `main.dart` read `currentConfiguration.uri.path`, which misses `push`ed routes | 2/13 |
| MEDIUM | Search fires 7–9 requests per query, no cancellation (stale ones now ignored) | 9 |
| LOW | Media notification small icon is the colour launcher icon (`mipmap/ic_launcher`) | 8 |
| LOW | 3 analyzer infos: `event_details_screen.dart:965,967`, `utils/date_format.dart:1` | 13 |
| INFO | Kept-alive tabs no longer refetch on every visit; screens relying on initState-per-visit may show older data until pull-to-refresh | watch in 2 |

---

## 7. Gotchas learned this session
- `CacheService.writePref` does NOT add `pref:` — see CLAUDE.md.
- Adventech Sabbath School API dates are `dd/MM/yyyy` calendar dates and are
  correct; lesson weeks start Saturday; days `01`–`07` plus supplements
  `hope-ss`, `inside-story`, `teacher-comments` dated Friday.
- `profiles` has no table-level SELECT for `authenticated`; column grants
  only (CLAUDE.md checklist).
- In a Home `initState` path, never notify a shell-level `ValueNotifier`
  synchronously during build — defer with a post-frame callback (see
  `_pendingFriendRequests` setter in `home_screen.dart`).
