# Batch 1 — Audit, bug fixes, Advent AI cleanup

Branch: `batch-1/audit-and-ai-cleanup` · Started 27 Oct 2026

## Environment

| Item | Value |
|---|---|
| Flutter | 3.41.9 (stable) |
| Dart | 3.11.5 (pubspec requires ^3.11.3) |
| Lib size | 404 Dart files, 80+ test files |
| Backend | Supabase (auth, Postgres + RLS + triggers, storage), Firebase (FCM, Crashlytics, Analytics) |
| Routing | go_router 14.8.1, top-level `GoRoute`s, root navigator key |
| State | Services with static `ValueNotifier`s + `StatefulWidget`s — no Provider/Bloc/Riverpod |
| Cache/offline | Hive via `CacheService`, `cached_network_image` with `adventImageCacheManager` |
| Audio | `just_audio` + `just_audio_background` (audio_service 0.18.18); `audioplayers` for voice notes |
| Video | `youtube_player_iframe` |

## Analyzer baseline (before any change)

`flutter analyze`: **0 errors, 0 warnings, 3 infos**

- `lib/screens/events/event_details_screen.dart:965,967` — curly_braces_in_flow_control_structures
- `lib/utils/date_format.dart:1` — dangling_library_doc_comments

## Fixed in this batch

### 1. Advent AI floated over private chats — HIGH
- **Problem:** Advent AI bubble appeared inside a conversation opened from Profile → Chat (and on Library, Settings, Home…).
- **Root cause:** `AdventAiBubble` was an app-wide overlay in `MaterialApp.builder` that hid itself by reading `routerDelegate.currentConfiguration.uri.path`. In go_router 14.8.1, `push` does not change that URI (`RouteMatchList.push` keeps the base `uri`), so `/users/<id>` → push `/messages/<id>` still reported `/users/<id>` and the bubble showed over the chat.
- **Fix:** Bubble removed entirely. Advent AI's sole entry point is the stationary button on the Chat inbox (`conversations_screen.dart`). AI screen, service, history and `/advent-ai` route untouched.
- **Files:** `lib/main.dart`, `lib/widgets/advent_ai_bubble.dart` (deleted), `lib/widgets/advent_ai_mark.dart`, `lib/screens/advent_ai/advent_ai_screen.dart`, `lib/screens/premium/premium_screen.dart`, `lib/screens/quiz/arena/quiz_boot_screen.dart`, `lib/config/router_config.dart`
- **Tests:** `test/advent_ai_placement_test.dart` replaces `advent_ai_bubble_test.dart` (which pinned the bubble onto Home/Library/Watch).

### 2. Sabbath School day chip ≠ content — HIGH
- **Problem:** Chip label disagreed with the reading under it.
- **Root cause:** `_dayStrip` indexed `['Sab','Sun','Mon',…]` with `date.weekday % 7`. Dart's weekday is Mon=1…Sun=7, so every label was one day early (Tuesday 27 Oct showed "Mon"). API dates were verified correct against live `sabbath-school.adventech.io` (2026-04 lesson 05). Also, three supplements (`hope-ss`, `inside-story`, `teacher-comments`) are dated Friday and were shown as extra weekday chips, and all highlighted as "today" on Fridays.
- **Fix:** `SsDay.chipLabel`, `SsDay.isDailyReading`, `ssWeekdayShort()` in the model; supplements get their own labels and an icon; never "today".
- **Files:** `lib/models/sabbath_school_model.dart`, `lib/screens/library/ss_lesson_screen.dart`
- **Tests:** `test/ss_day_labels_test.dart` — all 7 weekdays, month boundary, no timezone shift, supplements.

### 3. Android: music missing from system media controls — HIGH
- **Root cause:** `MainActivity` extended `FlutterFragmentActivity` (needed by local_auth) instead of audio_service's activity. audio_service then throws "The Activity class declared in your AndroidManifest.xml is wrong…", `MusicPlayerService._bootMediaSession` catches it and falls back to plain playback → in-app mini player only. iOS has no such requirement. True since the initial commit.
- **Fix:** `MainActivity : AudioServiceFragmentActivity()` — a `FlutterFragmentActivity` subclass, so biometrics keep working.
- **Side effect:** the Flutter engine is no longer destroyed with the activity (audio_service design).
- **Verification needed:** on-device Android test (notification, lock screen, Bluetooth buttons, biometric prompt).

### 4. Country cooldown "rejected but switched" — HIGH
- **Root cause:** `AuthService.updateProfile` wrote `country` to auth metadata (`auth.updateUser`) BEFORE the `profiles` upsert where `trg_country_change_cooldown` (patch_221) rejects it. The member saw the cooldown message, but metadata — read by `AuthService.currentCountry()` (Marketplace, Events, Jobs, Sabbath timer) and the profile header — already held the new country, while the row kept the old one.
- **Fix:** country is written to the row first in its own statement (same pattern as church/DOB); a rejection returns before metadata is touched. Edit Profile re-reads the row after a failed save, so the field shows the saved value and the baseline is correct for a retry.
- **Server-side enforcement:** already present and correct (BEFORE UPDATE trigger, row-locked, so concurrent saves serialise).
- **Files:** `lib/services/auth_service.dart`, `lib/screens/profile/edit_profile_screen.dart`
- **Remaining:** accounts already desynced need a one-off repair (metadata ← row). Awaiting approval.

### 5. Search showed stale results — MEDIUM
- **Root cause:** overlapping searches; `_runSearch` applied whichever response landed last.
- **Fix:** drop a response whose query is no longer `_lastQuery`.
- **File:** `lib/screens/home/search_screen.dart`

### 6. Blurry avatars in search results — MEDIUM
- **Root cause:** result rows used the stored Google URL (`=s96-c`, 96 px) directly, bypassing `photoUrlAtSize`.
- **Fix:** request 132 px (44 dp × 3).
- **File:** `lib/screens/home/search_screen.dart`

## Open findings (tracked for their batch)

| Sev | Finding | Batch |
|---|---|---|
| CRITICAL | Apple signing material committed: `AuthKey_5DP8YVY728.p8.pem`, `distribution.pem`, `distribution*.cer`, `profile_base64.txt`, plus stray `-in`, `-inkey`, `-name`, `-out` files. Rotate in Apple Developer, then remove from repo + history. | Needs owner action |
| HIGH | Onboarding pre-selects country from device locale (`onboarding_flow_screen.dart:63`, `Countries.detect()`), contrary to the explicit-selection requirement. | 12 |
| MEDIUM | ~20 avatar renders bypass `photoUrlAtSize` (seller, blocked users, member directory, composer, edit profile, onboarding…). | 9 |
| MEDIUM | `GlobalMediaBars` and 5 checks in `main.dart` read `currentConfiguration.uri.path`, which misses `push`ed routes — same blind spot as the AI bubble. | 2 |
| LOW | Media notification uses `mipmap/ic_launcher` (colour) as small icon — renders as a white blob on Android. | 8 |
| LOW | Search runs 7–9 requests per query with no cancellation; stale ones are now ignored but still cost bandwidth. | 9 |
| LOW | 3 analyzer infos (see baseline). | 13 |

## Not yet verified
- No Android/iOS device or emulator run in this environment.
- Full `flutter test` suite not yet run; targeted tests pending.
