# Advent Connect ZW — Session resume brief

**Repo:** `C:\Users\micha\Desktop\advent_connect_zw` · **Branch:** `main` · **Remote:** `https://github.com/mtechstudioszw/adventconnectzw`

## Where we are

- All 20 build stages from `ADVENT_CONNECT_ZW_MASTER_REFERENCE_V4 (1).md` are coded. Stage 20 is the **final** stage in that doc — there is no Stage 21.
- The app **compiles clean** (`flutter analyze` → No issues found).
- User has been testing on **Chrome** (`flutter run -d chrome`). Android build is blocked by a Gradle download issue — see Blockers below.
- 2,600 churches CSV has already been imported into Supabase by the user.

## Recent commits (latest first)

- `f15f028` Shrink event card + event hero + home church row
- `a0b0c30` Skip AdMob entirely on unsupported platforms (web/desktop)
- `f468d87` Fix AdsService: pass required dismissal callback to UMP consent form
- `7798f71` Release prep + UI polish: signing, AdMob env, UMP consent, launcher icons
- `b3febe2` Finish Stage 20 wire-ups: home cache, message outbox, distance chip

## What landed last session

**Stage 20 wire-ups**
- **Home feed cache** in `lib/screens/home/home_screen.dart`. Writes `{events, churches}` to Hive key `home_feed` after successful load; hydrates from cache on cold start when offline or when network fetch fails.
- **Offline message outbox** in `lib/services/messaging_service.dart`. Hive box `message_outbox_v1`. New `OutboxQueuedException` thrown when offline; `startOutboxFlusher()` subscribes to `ConnectivityService.onChanged` and drains on reconnect. Booted from `main.dart`. `chat_screen` shows "You're offline. We'll send this when you reconnect." snackbar.
- **Distance chip on church cards** — `ChurchCard.distanceLabel` (optional). Computed by `churches_screen._distanceLabelFor()` using `LocationService.formatDistance`.

**Release plumbing (no real values plugged in yet)**
- `android/app/build.gradle.kts` reads `android/key.properties` at config time. Uses real keystore for release when present, falls back to debug key when absent. Also injects `admobAndroidAppId` into `AndroidManifest.xml` via `manifestPlaceholders["admobAppId"]`.
- `ads_service.dart` — production banner IDs come from `--dart-define=ADMOB_ANDROID_BANNER` / `ADMOB_IOS_BANNER`. UMP consent (`ConsentInformation` + `ConsentForm.loadAndShowConsentFormIfRequired`) runs before `MobileAds.instance.initialize()`.
- `scripts/build_release.ps1` + `.sh` — one-shot wrappers around `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info` with the dart-defines.
- `pubspec.yaml` gained `flutter_launcher_icons: ^0.14.4` (dev dep) + config block with navy `#0D1B3E` adaptive background. Needs `flutter pub get` before use.
- `.gitignore` excludes `android/key.properties`, `*.jks`, `*.keystore`.
- New: `android/key.properties.example`, `assets/icon/README.md`, `scripts/build_release.*`.

**UI fixes from user testing**
- Home screen "Discover churches" section: converted from a 2-col grid to a **horizontal-scroll row** of 150-wide tiles, height 160. Mirrors the Events row right above it. (Earlier `childAspectRatio` tweaks were superseded.)
- `EventCard` (Events tab list) rewritten as a **compact horizontal card** (76×76 thumbnail with date pill overlay + title + date/time + location + RSVP), matching `ChurchCard`. Per-card height ~320 → ~110.
- Event details hero: `AspectRatio(1) → SizedBox(height: 260)`. Same fix pattern as church details.
- Church details hero: `AspectRatio(1.0) → SizedBox(height: 180)` (was eating half the screen).
- Prayer screen: removed `_PostPrayerSheet` (simplified modal) and `_ShareFab` (floating pill that overlapped the gold FAB). Both entry points now route to the full `post_prayer` screen.

**Web-runtime fixes (Chrome testing)**
- `AdsService.initialize()` and `.bannerUnitId()` short-circuit when not on Android/iOS. `google_mobile_ads` has no web/desktop implementation; calling UMP methods there throws `MissingPluginException` asynchronously which a try/catch around a void-returning method can't intercept. `_isAdMobSupported` getter handles both `kIsWeb` and the `dart:io` `Platform` throw on non-mobile.
- `ConsentForm.loadAndShowConsentFormIfRequired` requires a dismissal callback (`OnConsentFormDismissedListener`) — calling it with no args was the original build error. Now passes a debugPrint-only listener.

**Analyze fixes (already merged)**
- `analytics_service.dart messageSent` — `{'source': ?source}` (null-aware on value, not key).
- `connectivity_service.dart _sub` — documented + `// ignore: unused_field`.
- `shimmer_loaders.dart` — `(_, __)` → `(_, _)`.
- `church_model.dart copyWith` was dropping lat/lng — fixed.
- `messaging_service.dart` — dropped redundant `package:hive/hive.dart` import.

## Blockers (user action items — code can't fix)

1. **Crashlytics buildtools jar** — first Android build needs to download `firebase-crashlytics-buildtools-3.0.2.jar` from `dl.google.com`. User's connection times out / DNS misses. **Needs one trip to a faster connection**, after which it caches forever.
2. **Upload keystore** — `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. Then `cp android/key.properties.example android/key.properties` and fill in.
3. **AdMob app + 5 banner ad units** (Home, Churches, Events, Marketplace, Jobs). Copy IDs into `key.properties` (app id) and pass to `build_release` script via env (banner id).
4. **Launcher icon** — 1024×1024 `assets/icon/app_icon.png` + `app_icon_foreground.png`. Then `dart run flutter_launcher_icons`.
5. **Google sign-in OAuth clients** on Google Cloud Console: Web (for Chrome) + Android (debug + release SHA-1). Paste into Supabase Auth → Google provider. Until then the Continue-with-Google button errors with "OAuth client not found".
6. **Privacy Policy + Terms** hosted publicly — Play Store listing requires URLs.
7. **iOS `GADApplicationIdentifier`** in `ios/Runner/Info.plist` is still the test ID — swap manually before any iOS release build (Android is automated, iOS is not).

## User memory + non-obvious context

- **Bandwidth is limited.** Do NOT run `flutter pub get` / `pod install` without asking — see `~/.claude/projects/.../memory/feedback_network.md`.
- **CLAUDE.md is authoritative** for colors, fonts, layout. Note the recent UI fixes softened the "all uploaded images square" rule for the detail hero only — list/grid thumbnails still respect it.
- **Crashlytics SDK at runtime** still works on debug — only the **buildtools Gradle plugin** is the issue.
- **The `_useTest` flag in `ads_service.dart` is `kDebugMode`-only.** Release builds use the production ID (which defaults to the test ID if `--dart-define` is missed). Safe by design.
- **`unawaited` everywhere matters** — Hive flush, cache write, audio-stop on dispose. Don't await them on hot paths.
- **`OutboxQueuedException`** is a soft success — `chat_screen` clears the input on this, only the generic catch shows a failure snackbar.
- **`google_sign_in 6.3.0`** still has the v6 API (`signIn()` / `.authentication`) — v7 hasn't been adopted, don't rewrite to the v7 shape.

## Suggested next builds (in priority order)

1. **Once user has cleared blockers 1–6:** produce the first signed `.aab` via `.\scripts\build_release.ps1`, upload to Play Console internal track, smoke-test on a real device. *No code work, but verify the script actually runs end-to-end.*
2. **iOS xcconfig setup** so `GADApplicationIdentifier` injects from build time too (mirror what we did on Android via `manifestPlaceholders`).
3. **Notification trigger sweep** — walk Part 23 of the master ref and confirm every listed trigger has a sender. Likely gaps: event reminders, RSVP confirmation, urgent banner push.
4. **Admin Dashboard** (Part 37) — separate web codebase (Retool first, Next.js later). Build only after the app has real users.
5. **Beta launch instrumentation** — feature flags, in-app feedback form, version-update gate.

## What NOT to redo

- `flutter pub get` — packages are installed.
- Stage 20 wire-ups (cache / outbox / distance) — done and committed.
- Analyze cleanup — clean.
- Dependency version research — `google_sign_in 6.3.0`, `image_cropper 8.1.0`, `connectivity_plus 6.1.5`, `hive 2.2.3`, `hive_flutter 1.1.0`, `local_auth 2.3.0`, `geolocator 13.0.4`, `google_mobile_ads 5.3.1`, `shimmer 3.0.0` all verified.
- The simplified `_PostPrayerSheet` — deleted intentionally; all entry points must go to `post_prayer` (Title + Privacy + Urgent).
- The old full-bleed `EventCard` with 16:9 cover and big body — the compact horizontal version is intentional; don't restore the photo card style for the list view.
- The home churches 2-col `GridView` — replaced by a horizontal `ListView.separated`. Don't put it back as a grid.
- `AdsService._isAdMobSupported` — keep the guard. Any AdMob call on web/desktop will async-throw `MissingPluginException`.
