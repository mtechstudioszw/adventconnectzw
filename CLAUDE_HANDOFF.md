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
2. Core app shell, Home, Marketplace, Profile — **IN PROGRESS** (redesign pass 1 done; acceptance needs a device check by the owner — see `docs/BATCH_2_REPORT.md`). Was marked done too early on 28 Oct; reopened.
3. Library information architecture & design — **PART 1 DONE 29 Oct 2026**
   (Library tab replaced Watch; Library home; Watch moved inside with every
   route kept; Home: devotion opens `DevotionScreen`, Continue row, Watch row).
   **Part 2 DONE 29 Oct 2026:** Library-only search (Bible refs + verse
   text, hymns, EGW titles, beliefs; never social), Saved & downloads
   (Bible bookmarks/highlights/notes, favourite hymns, saved + downloaded
   EGW books), "All resources" directory (real content only, with format,
   source, language, offline), 28 Beliefs (`lib/data/fundamental_beliefs.dart`
   — OUR summaries, official text linked; **needs a pastor's read before
   wide release**). Not built, because the content isn't licensed/available
   yet: heritage, Church Manual, Yearbook, study guides, children's
   resources, dictionaries/concordance. Next: Batch 4 (Bible).
   **Library tools DONE 29 Oct 2026:** reading plans
   (`reading_plan_service.dart`, verse-balanced, 5 plans), memory verses
   (`memory_verse_service.dart`, spaced practice, "Memorise" in the Bible
   reader's selection bar), Sabbath hours (`sabbath_hours_screen.dart`;
   SabbathService gained opt-in GPS + `sunsetOn`). Reminders are
   `LibraryReminders` — absolute instants re-armed on every app start.
   **AndroidManifest had NO flutter_local_notifications receivers**, so
   every zonedSchedule reminder (incl. the older Watch reminders) never
   fired on Android; receivers + RECEIVE_BOOT_COMPLETED added — verify on
   a real Android build.
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
  - **NEW (Batch 2):** the five tabs — Home, Library (`/library`, name
    `library_hub`; Watch until 29 Oct 2026), Chat (`/messages`),
    Marketplace, Profile — are a `StatefulShellRoute.indexedStack` rendered by
    `lib/screens/widgets/tab_shell.dart`. Tabs stay alive when you switch.
  - Every **direct child route of a tab** carries
    `parentNavigatorKey: rootNavigatorKey` so it still opens full-screen above
    the island. A new child route without it will open inside the tab.
  - **Watch is no longer a tab** (29 Oct 2026). Its routes (`watch`,
    `watch_video`, …) are top level, unchanged, so push it — never
    `goNamed('watch')`. The Library reader is `library` at `/library-read`,
    also top level: it is pushed from every tab, and inside the Library
    branch it would switch the island underneath the caller.
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
- **Seller profile (fixed):** pending / rejected / banned / deactivated
  shops opened for buyers with their products (patch_031 rule only held
  in the grid and product details) → now "This shop isn't open" for
  everyone but the owner. A missing seller row no longer falls back to the
  stale copy from the rail. Offline from the rail said "no products" →
  now "Couldn't load products". Error card had a fixed "Seller not found"
  title for every failure. Offline save no longer says "Sign in".
  Test: `test/seller_profile_states_test.dart`. Full suite: **786 passed**.
- **Checkout duplicate-order bug (fixed):** `place_order` and the read-back
  `fetchById` shared one try, so a signal drop between them reported a
  placed order as failed and kept it in the basket → tapping again sent a
  duplicate. And a null read-back cleared the basket but said "Could not
  place the order". Now the basket clears as soon as the create succeeds;
  an order that can't be read back gets a "saved — open My orders" snackbar.
  Offline failure says offline. Test: `test/checkout_duplicate_order_test.dart`
  (fails on the original code). Full suite: **787 passed**.
- **Orders (fixed in app):** `OrderService.updateStatus` treated an
  RLS-refused update (0 rows, no error) as success → now `.select('id')`
  and throws on empty. Seller "Decline" and buyer "Cancel" now confirm
  first (irreversible, was one tap). Test: `test/order_status_update_test.dart`.
- **Orders (needs owner): `database/patch_270_order_status_transitions.sql`
  — DRAFT, NOT RUN.** Live DB check: `orders_update_party` lets either
  party set ANY status; a buyer can mark their own order confirmed /
  completed via the API, and closed orders can be reopened. The patch adds
  a transition guard matching the app's buttons. Review, then run.
- **Live DB facts that disagree with the docs (28 Oct 2026, read-only):**
  - Supabase project `adventconnectzw` is in **eu-central-1 (Frankfurt)**,
    not Africa (Cape Town) as CLAUDE.md says. Not changed — moving region
    means a new project + migration; owner's call.
  - `orders`, `order_items`, `place_order` and `orders_freeze_financials`
    exist live but are **not in `database/`**. The repo can't rebuild the
    DB as it is.
- **Profile went stale (regression from keep-alive tabs, fixed):** Home
  says "Posted — see it on your profile" and the post wasn't there until
  restart; friend/church counts too. New `TabShell.activeIndex` notifier
  (set post-frame from the shell's build, so every route into a tab is
  seen); Profile refreshes on return, throttled to once per 10s.
  Use the same notifier for any other kept-alive tab that goes stale.
- **New posts missing from their own list (fixed):** every create screen
  popped `true`, every list ignored it. `PostFab(onCreated:)` wired on
  Jobs, Events, Prayer, Marketplace. Test: `test/post_fab_on_created_test.dart`.
  Full suite: **790 passed**.
- **Marketplace findings NOT fixed (need a decision):**
  - `fetchProducts` sends every approved seller id in the URL
    (`inFilter('seller_id', …)`). Fine now; at a few hundred sellers the
    URL gets long enough to fail. Proper fix is server-side (a view or RLS
    join) = schema change → owner approval.
  - `CategoryScreen` (`/marketplace/categories`) is unreachable — nothing
    links to it — and it ignores the country scope. Remove or relink.

- Profile + Edit Profile avatars now request the circle's pixel size.
- End of batch: `flutter analyze` → **No issues found**; `flutter test` →
  **790 passed**. Report: `docs/BATCH_2_REPORT.md`.

### After Batch 2 — founder screenshots, 28 Oct 2026 (fixed)
- Founder's phone runs an OLD build (Advent AI bubble on every screen,
  composer + Donate on Home). None of these fixes are on it yet.
- Product tiles / shop page / basket said "Seller": `products` has no name
  column. `MarketplaceService._fetchApprovedSellers()` now returns
  id → business_name and fills `seller_name`.
- Condition showed raw ("new", "like_new") → `Product.conditionLabel`.
- Shops rail ignored the Zimbabwe/Worldwide scope (Kumasi shop shown).
- Music titles were raw file names → `titleFromFileName` on upload;
  **`database/patch_271_music_titles_cleanup.sql` DRAFT, NOT RUN** fixes
  the 11 existing rows (ids 99–110; 102 and 108 are the same hymn).
- Sabbath School: same-title editions now show their edition ("Easy
  Reading"); Home and Library share `pickCurrentQuarterly`.
- Jobs: shared link to a deleted job crashed; Hiring/Offering switch never
  saved on edit; Mark filled/Reopen dropped 5 fields (`Job.copyWith`).
- Silent zero-row writes → `utils/require_changed.dart` on owner edits and
  deletes in jobs, posts, comments, prayers, prayer comments, events,
  news, products. **Not stories**: `stories_select_active` hides expired
  stories from their author, so a select-back would skip the delete.
  Live RLS checked for every table touched (deleter can also SELECT).
- Unused `/marketplace/categories` screen deleted.
- Live DB: 13 approved sellers (ZW 11, GH 1, TZ 1) — the seller-id URL
  limit is far off.
- Full suite: **799 passed**; `flutter analyze` clean.

### Marketplace medical claims (28 Oct 2026, founder: "do it")
- Rule "No medical claims" + "Prescription medicines" in the seller Code of
  Conduct (`marketplace_guidelines_screen.dart`).
- `utils/medical_claims.dart` blocks saving a listing whose title,
  description or subcategory names a disease (list of conditions, not
  verbs — see its comment for words deliberately left out).
- "Report listing" on every product not your own → `reports` with
  content_type 'product' (already supported; shows in admin-web Reports).
- "Hide listing (admin)" for super admins → RPC `admin_set_product_status`
  in **`database/patch_272_admin_product_moderation.sql` — DRAFT, NOT RUN.**
  Until it runs the button says so. It also notifies the seller.
- Theopath not banned (founder agreed). Once patch_272 is run, hide the
  disease-claim listings from the app.
- Tests: `medical_claims_test`, `product_moderation_test`.
- **Report gap closed:** Report on stories (viewer header), post comments,
  prayers (app bar), prayer comments, events, jobs, news — never on your
  own. Already had: posts, messages, groups, profiles, sellers, products.
  Test: `report_buttons_test`.
- **Theopath listings 42 HYPERTENSION KIT, 43 SUGAR DIABETES KIT, 44 GENITAL
  WARTS KIT set to status 'removed' on the live DB (28 Oct 2026, founder
  said "ban product")**, seller notified for each. Reversible: set status
  back to 'available'. The six capsule listings (hedged wording +
  disclaimer) left up.
- **Moderation + appeal (founder, 28 Oct 2026):**
  - `database/patch_272_moderation_hide_and_appeal.sql` — **DRAFT, NOT
    RUN** (replaces the old unrun patch_272). Adds
    `moderation_hidden_at` / `moderation_reason` to products and posts; a
    guard trigger (only super admins change them; a seller can't re-show a
    moderated listing — before this they could undo the ban themselves); a
    RESTRICTIVE select policy hiding moderated posts from all but author +
    admins; an admin read policy on products; RPCs
    `admin_set_product_status` / `admin_set_post_hidden` that notify with
    reference_type `moderated_product` / `moderated_post`; backfills 42–44.
  - App: `widgets/moderation_appeal_sheet.dart` (Appeal sheet — WhatsApp
    +263778092494 / adventconnectzw@gmail.com from `support_sheet.dart`,
    prefilled with item, link, reason; `ModeratedBanner`; reason dialog),
    `widgets/moderation_actions.dart` (`moderatePost`). Admin "Hide/Restore
    post" in the post menu (Home, user profiles); "Hide/Restore listing" on
    product details; seller dashboard shows "HIDDEN BY MODERATORS" and its
    toggle becomes Appeal. Notification centre + push tap open the appeal.
  - Posts on other people's profiles had no menu → now Report (+ admin).
  - `Post.copyWith` was dropping `country` — fixed.
  - Test: `moderation_appeal_test`. Full suite **812 passed**.
- **Redesign pass 1 (28 Oct 2026), checked with renders from
  `test_screens/` (`flutter test test_screens/<x>_shot.dart`, PNGs to
  $SHOT_DIR; outside test/, not in CI):**
  - Marketplace: compact horizontal shop cards; product tiles as cards with
    square photos (CLAUDE.md rule); Material-icon chips, selected = blue;
    skeleton matches. Ambient field: `AmbientPainter(ghosts: false)` behind
    real screens (CLAUDE.md updated).
  - Profile: 3 numeric stats, church line under the name, one "How you
    serve" invitation, blue completion ring (one gold per screen).
  - Jobs: model read salary_min/max + list requirements but DB has
    `salary_range` text + text requirements → every job "Negotiable", no
    requirements; flags/email never read and wiped by edits. All fixed;
    cards show level + Sabbath/SDA badges; details has Email the poster.
  - Home: Quick stats "Prayers" tile was hard-coded '0' (fake) → removed;
    Quick stats hidden when empty; Stories lost its "Prayer" link; end-of-
    feed buttons no longer run edge to edge.
- Plain data writes via execute_sql go through; DDL (patch 270/272) asks
  for approval, which times out.
- Supabase `apply_migration` approval prompts timed out 3× (never reached
  the founder). Patches 270/271/272 are for the founder to run in the SQL
  editor; read-only checks work fine.

### MAJOR REDESIGN BRIEF (owner, 28 Oct 2026) — now the governing scope
for Home, Profile, Marketplace, storefronts, product detail and Jobs. Plan,
audit and stage table: **`docs/REDESIGN_PLAN.md`** (read it first). The
13-batch prompt still governs everything else. Ghost outlines question is
settled by the brief: removed, plus dust dots, glow halved
(`AmbientPainter(quiet: true)`).

### Prompt-compliance notes (28 Oct 2026, owner asked)
Work done OUTSIDE the current batch, recorded against the batch it belongs
to so those batches don't redo or overlook it:
- Batch 5 (Sabbath School): Today card → today's reading; edition labels;
  shared `pickCurrentQuarterly`.
- Batch 8 (music): upload titles cleaned; patch_271 drafted.
- Batch 9 (search): `orFilterValue` quoting in 6 services.
- Batch 13 (QA): the 3 baseline analyzer infos fixed.
- Owner-requested, not in any batch: moderation + appeals (patch_272),
  report on all user content, medical-claims rule, order-status guard
  (patch_270).
- Ghost outlines: settled by the owner's redesign brief (remove).
- Before each batch: post objective, systems touched, files, risks and
  decisions needing approval, then wait for decisions.

### Resume point (exact)
**Major redesign brief governs (docs/REDESIGN_PLAN.md).** Stages 1–3 code
done (28 Oct 2026). Stage 3 = shared `ProfileHeader`
(lib/widgets/profile/profile_header.dart) on both profile screens,
one-way follows (`FollowService`, patch_274), Followers / Following /
Requests screen, Edit profile Website + Private account, post-menu
Follow/Unfollow. Soft profile glow (owner-approved palette exception,
see CLAUDE.md). Stage 4 = organization Pages (patch_275; see
docs/REDESIGN_PLAN.md "Stage 4 notes" — churches deliberately not
migrated). Stage 5 = marketplace ranking/filters/shelves + patch_276
security guard. Stage 6 = product page, storefront, basket, real view
counts + server medical-claims rule (patch_277). Stage 7 = Jobs landing,
detail, stepped posting, saved jobs, My job posts + patch_278 (security:
posters could self-publish). Jobs v2: Find work / Hire, every kind of work,
structured pay, Quick apply + Applicants, job alerts, My jobs hub.
patch_279: reports show what/who and admins can Remove / Remove & ban. **Next: Stage 8 — premium foundations (no
prices).**

Older note, kept for the record:
**Batch 2 is IN PROGRESS (awaiting owner device check). Next: Batch 3 — Library information architecture &
design** (see the master prompt). Owner items from the Batch 2 report
(patch_270 review, Supabase region, repo missing the orders schema) are
waiting on the owner, not on code.

Batch 2 items that were planned (kept for the record):
1. Home polish: card visual pass (states done)
   (keep CLAUDE.md colours, Poppins, flat headers, transparent scaffolds).
2. Marketplace audit + redesign (listing cards, categories, search/filters,
   empty/loading states). No new checkout/payment features without approval.
3. Profile redesign (layout, identity, avatar quality, actions). Profile →
   Chat must open the normal conversation (already fixed — keep it so).
4. End-of-batch report + full `flutter analyze` + full `flutter test`.

---

## 5. Pending owner actions

0. **DONE 28 Oct 2026:** patches 276, 270, 271, 272, 273, 274, 275, 277,
   278, 279 were applied to the live database in that order (via the
   Management API, at the owner's request) and verified: every trigger,
   table, column and function present; a rolled-back smoke test as an
   ordinary member confirmed jobs land 'pending' with a 30-day expiry and
   can't be self-published, alerts and report-owner stamping work.
   Still the owner's call: patch_271 left hymn duplicate id 102/108.

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
