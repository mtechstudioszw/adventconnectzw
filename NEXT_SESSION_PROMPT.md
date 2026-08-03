# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (3 Aug 2026)

All work is pushed. `main` head: **`c3e06d6` "ads fix"**.
`flutter analyze` clean apart from **4 pre-existing infos**;
**242/242 tests pass** (was 135 two sessions ago).

Shipped last session: the whole premium subscription, the feature-usage
analytics backend, the Events/Churches pinned-ad fix, the live-stream
thumbnail fallback, and a search-screen spacing fix.

Applied to production — **do NOT re-apply**:
`20260803120000_premium_subscriptions.sql`,
`20260803130000_payment_receipt_essential.sql`,
`20260803140000_usage_analytics.sql`.
Deployed: `verify-purchase` v1, `play-rtdn` v1, `notify-fcm` v17.

## Read first

1. `CLAUDE.md` — headers are **FLAT on `palette.scaffoldBg`, never navy**.
2. Memory: `premium-subscription-task`, `admin-console-analytics-findings`,
   `quiz-arena-decisions`, `founder-quality-bar`,
   `motion-must-not-cost-time`, `audio-background-playback-fix`,
   `repo-and-environment`, `brief03-open-bugs`.
3. `git -C adventconnectzw log --oneline -12`

## The rule that keeps paying — repeat it

**Verify the premise before building.** Last session that turned one
"build this" into "already fixed", and caught four bugs that each failed
**silently**. Several items below already have their premise checked —
those notes save you the wrong turn, so read them before coding.

---

# WEB ADMIN DASHBOARD — DECIDED, but DEFERRED

**Founder's call (3 Aug 2026): "I will build UI soon after all bugs are
finished."** So do **NOT** start the console this session. Clear the
22-item bug batch below first; the console comes after.

The decisions are already settled — **do not re-litigate them** when the
time comes, just build:

- **Web admin only.** The in-app Flutter admin is explicitly out of scope.
- **`admin-web/` is the app in real use** — git proves it (touched
  7 Jul 2026; the Next.js `admin/` has been stale since 22 Jun). It is
  the thing being replaced.
- **STACK: Next.js**, built in `admin/` (it already has App Router, auth
  middleware, server actions and Tailwind). *Rationale, since the
  founder's brief said "Flutter Web / Material 3":* every product the
  brief named as the bar — Supabase, Linear, Stripe, Vercel, Notion,
  GitHub — is a web app, and Flutter Web has slow first paint, poor text
  selection, weak accessibility and a heavy bundle. All four are
  disqualifying for a console that non-technical staff will check on a
  phone. Material 3's *look* can still be honoured in CSS.
- **DEPLOY: Vercel** (canonical for Next.js, free tier is enough).
  Fallback Netlify, which the founder already uses for `admin-web/`.
  The Vercel connector is **not** authorised in the agent session, so the
  founder connects the repo themselves; set the publish root to `admin/`.
- **Migrate anything `admin-web/` has that `admin/` lacks** — it has 14
  tabs (Overview, Users, Sellers, Reports, Feedback, Church claims,
  Church admins, Churches, Events, Jobs, News, YouTube, Broadcast, Usage)
  against the Next.js app's 7. **Do not delete `admin-web/` until the
  replacement is deployed and the founder has signed off** — it is their
  only working console today.

**Access to the current console, for reference:** open
`admin-web/index.html` directly in a browser (single file, no build).
Sign in with the founder's app email/password; the page checks
`profiles.is_super_admin` and signs out anyone else. Verified 3 Aug: the
founder is the **sole super admin**, and all 35 RPCs the page calls exist.

**Backend already built for it, live and attack-tested, but NOT called by
any UI yet** — so nothing new is visible in the console today:

- **Analytics:** `admin_feature_usage`, `admin_active_users_series`,
  `admin_platform_breakdown`, `admin_premium_stats`.
- **Staff roles + audit log** (`20260803150000_staff_roles_and_audit.sql`).
  There were previously **no roles, no permissions and no audit log** —
  `assert_super_admin()` is one boolean and the founder was the only
  holder, so hiring anyone meant handing them the power to ban users and
  broadcast to everyone with no record of who did it. Now four roles:
  `viewer` (read only), `moderator` (daily job, **contact details
  masked**), `manager` (+ PII + audit log), `owner` (+ ban and mass
  broadcast). Additive: all 35 existing RPCs still call
  `assert_super_admin()`, which now also accepts a staff `owner`, and the
  founder is seeded as owner. Use `assert_staff('moderator')` for new
  work and call `log_admin_action(...)` from every mutating RPC.
  **The console's People/Settings sections should manage staff via
  `admin_list_staff()` / `admin_set_staff_role()` — nobody should be
  setting `is_super_admin` by hand any more.**
**What genuinely has no data source** (do not promise these): crash
reporting (Crashlytics lives in Firebase), ad impressions/CTR/eCPM
(AdMob-side), country/city, session duration, retention cohorts, and all
infrastructure metrics. Say so rather than shipping empty charts.

---

# TURN ONE — two things to ask before any code

**1. #7 — is the ad fix even on the founder's phone?** They report the
Events/Churches banner "taking the full screen" AFTER the fix was pushed.
**Full APK builds are blocked on this machine**, so the fix only reaches
a device via CI (`.github/workflows/build-apk.yml` / `build-aab.yml`).
**Ask whether they installed a build made from `c3e06d6` or later.** If
yes, this is a NEW symptom (full-screen, not merely pinned) and must be
reproduced before touching anything — do not re-fix blind.

**2. #6 — the QR-code logo. The founder never sent the file or the
location.** The message ends "its in this location:" with nothing after
it. **Ask for the image and the exact screen.** Only the QR code gets
this logo, nowhere else. (Best guess if they confirm: the friend-QR sheet,
`showFriendQrSheet` / `lib/widgets/.../friend_qr*`, which already has a
render test in `test/friend_qr_test.dart`.)

---

# THE BATCH — 22 items

## A. QUIZ — the biggest piece (#3)

The founder wants a **real quiz game**, and asked to discuss the design
before it is built. Four parts:

### A1. Sound is still silent
**Premise already checked — do NOT go hunting for missing files.** All
nine WAVs exist in `assets/sounds/quiz/` (tap, tick, count, go, correct,
wrong, combo, levelup, finish) and `assets/sounds/quiz/` IS declared in
`pubspec.yaml:195`. `QuizSfx` (`lib/services/quiz_sfx.dart`) is fully
written, with per-clip volumes and a deliberate "never steal audio focus"
design (Android `AndroidAudioFocus.none`, iOS `ambient`) so the Library
music player is not interrupted.
So the bug is **playback/lifecycle**, not assets. Prime suspect is the
race already documented in memory `quiz-arena-decisions`: *"publishing
into a shared pool as you build it races with disposal — that is what
silenced the quiz. Stage locally, publish once, guard with a generation
counter."* Check whether that regressed, and whether `ambient`/`none`
focus is silently muting on the founder's device.

### A2. Background music while playing
A looping track for the duration of the arena, like a real game. Must
**not** fight the Library music player — see
[[audio-background-playback-fix]]; the platform-swap bug there killed
music three times. Duck or stop the loop if the user's own music is
playing.

### A3. A real sound/haptics settings screen
In the **main app settings**, not buried: separate controls for **music**,
**sound effects**, and **vibration/haptics**. Persist per user.

### A4. Crash: `Null check operator used on a null value`
Fires when the countdown reaches zero **before the user answers**.
Existing rule (memory `quiz-arena-decisions`): **timeout = wrong answer**.
The quiz round screen has **no test** for the timeout path and needs an
`autoStart` seam — this has been outstanding for three sessions.
**Reproduce it in a test first; let the test find the null.**

### A5. Quiz profiles + real multiplayer — DESIGN BEFORE BUILDING
The founder's ask:
- A **quiz profile** (own display name + photo, editable inside the quiz).
- Without one you may still play for fun, but **no leaderboard entry and
  no challenges**. (Recommended over blocking play entirely — a hard gate
  on first open loses users.)
- Challenge **anyone on the app** with a profile, not just friends.
- **Live head-to-head**: both players get the same question at the same
  time and must answer before the timer hits zero, like a live game show.

**Design constraints that must be handled — the founder explicitly asked
for the downsides to be designed for:**
1. **Server-authoritative timing.** Never trust client clocks. The match
   row carries `question_started_at` from the server; each client counts
   down from that, not from when the packet arrived. Otherwise a 300ms
   slower connection silently loses every race.
2. **Never ship the correct answer to the client before the answer locks.**
   The current single-player screen has `_question.correctIndex` on the
   client — fine solo, fatal in a competitive match.
3. **Score on the server.** Submit via an RPC that stamps arrival time and
   returns only "locked"; reveal correctness once both have answered or
   the timer expired.
4. **Opponent disconnects / rage-quits.** Must never hang the other
   player. Forfeit after the question timer + a grace window.
5. **Reconnect mid-match.** App backgrounded → rejoin and catch up to the
   current question index.
6. **Matchmaking at 170 users (DAU 73) will usually find nobody.**
   This is the single biggest practical risk. Strong recommendation:
   **async-first, live-when-possible** — the match is a persistent record;
   if both are online it plays live, otherwise each plays their run and
   the result resolves when the second finishes. A pure live queue will
   feel dead at this scale.
7. **The Realtime channel has the same publish/dispose race** that already
   silenced the quiz — guard with a generation counter.
8. Challenge notifications are **not** essential, so they are correctly
   suppressed during Sabbath quiet hours. Confirm that is wanted.

Suggested shape: `quiz_profiles` (display name, photo, rating, W/L),
`quiz_matches` (both players, question set fixed at creation, current
index, `question_started_at`, status), `quiz_match_answers` (server-stamped).

## B. PREMIUM CORRECTIONS

- **#4 — the Premium entry is in the wrong place. My mistake.** Move it
  into the existing **⋮ bottom sheet** on Profile: the `more_horiz`
  button at `lib/screens/profile/profile_screen.dart:516` opens a sheet
  at :527 containing 'Sabbath timer' (:562) and 'Sign out' (:567). Put
  Premium there, and **remove the star `HeaderIconButton` I added at
  ~:1231** — the founder says it looks bad top-right. (Settings entry and
  settings-search entry stay.)
- **#5 — copy now lies.** Several screens still say the app is free,
  especially the **donate screen and its card**. Audit every "free"
  claim and correct it now that a paid tier exists.

## C. ADS (#7)

See TURN ONE item 2 first. Related: last session added
`lib/widgets/ads/scroll_aware_ad_footer.dart`, a drop-in
(`body: ScrollAwareAdFooter(child: …)`) that makes a bottom banner
collapse on scroll. It is **built and tested but not yet used anywhere** —
it exists so the previously-reverted detail-screen placements (product /
event / church, commits `c18cd7f` → `13d55c0`) can come back safely.

**Ad revenue expansion** (audited, founder wants it — build only what
they pick): restore product/event/church detail + seller storefront;
then search results, Advent News, notification centre, member directory;
Library browse lists need a faith-sensitivity call (**recommend no ads in
the Bible reader**); and the highest-value idea — **more rewarded ads**
(currently only quiz lifelines), e.g. "watch an ad to boost your listing
24h". **Never**: Chat, auth/signup/login, Prayer, and never for premium
users. Those exclusions are currently correct — verified.

## D. PLAYERS / MINI-PLAYERS (#8, #9)

**Music (#8):**
- Opening the full player leaves the mini player visible underneath —
  it must hide while the full player is up and return on exit,
  automatically.
- Mini player should be **draggable** to top / middle / bottom.
- Closing the mini player must **stop playback immediately**.
- **Shuffle does not work.**
- **Download-for-offline does not work** (or appears not to).
- The mini player's shape is wrong — a long horizontal bar. It should
  read like a small video card.

**Watch (#9):**
- Same hide/show rule for its mini player.
- Make it a **real YouTube-style floating player**: draggable and
  resizable, with video actually playing inside it.
- **Remove the follow button** from Watch.

Beware [[audio-background-playback-fix]] — the platform-swap bug killed
music three times. Do not swap `JustAudioPlatform.instance` casually.

## E. HOME / FEED (#1, #13, #14)

- **#1** Devotion card on Home clips the verse — **ellipsize long verses**.
  And **Verse of the Day** should, when tapped, open the Bible **scrolled
  to and highlighting that exact verse**.
- **#13** Show **two rows of "People to meet"**, surfaced at different
  times. Also asked: can the feed scroll endlessly, or must we wait for
  more posts? (At 170 users, honest answer: recycle/blend rather than
  fake infinite — say so.)
- **#14** Make the feed **algorithmic**: as traffic grows, certain
  modules (People to meet, quick stats) should reliably reappear.
  See memory `feed-ranking-findings` — it already documents how ranking
  works today and why fresh content loses.

## F. PROFILE / ACCOUNT

- **#12 Cache the profile screen** (friends list etc.) so it does not
  refetch every visit — then **audit other screens that refetch** and fix
  them too.
- **#15** Edit Profile says "Full name" but signup collects **name +
  surname**. Make them consistent.
- **#17** **Delete account and sign out must feel instant.** See
  [[motion-must-not-cost-time]] — celebrate after the fact, never block.
- **#18** New **exit-survey screen on account deletion**: ask why they
  are leaving, say we are sorry to see them go, store the reason, and
  **surface it in the web admin dashboard**.
- **#19** The **"how did you hear about us" survey no longer appears on
  first signup.** Premise partly checked: `SignupSurveySheet` exists at
  `lib/widgets/home/signup_survey_sheet.dart` and is called from
  `home_screen` after ~1200ms; it is gated by
  `SignupSurveyService.shouldPrompt()`. **Check that gate first** — and
  note patch_180 records that every non-admin submit used to fail. Also
  confirm the premium promo added last session (6s delay) is not
  swallowing it; it should not, since the promo refuses when another
  sheet is up.
- **#20 Cross-account data leak (SECURITY — treat as high priority).**
  A new account briefly showed the **previous account's data for ~1
  second** before correcting. Some cache or in-memory service is not
  cleared on sign-out. Audit every static/`ValueNotifier` service for a
  sign-out reset. Note `PremiumService.clear()` and
  `UsageAnalytics.stop()` were wired last session; others may not be.

## G. BIOMETRICS + BAN EVASION (#21)

**Bug — premise CONFIRMED, exact cause found.** Biometric unlock is
device-level, not per account: `'biometric_enabled'` is listed in
`SecureStorageService._preservedKeys` (`secure_storage_service.dart:49`),
which is the deliberate "survives sign-out" set. So Account B inherits
Account A's biometric setting on the same phone.
**Fix:** key the preference per user id (or store it on the profile), and
clear the active biometric session on sign-out. A new account must start
with biometrics **off** until it opts in. Careful: that preserved-keys
list exists for good reasons (the intro-onboarding flag) — only move the
biometric key, do not empty the set.

**Feature — ban-evasion detection.** Risk *scoring*, never a single
identifier: device install id, push token, IP patterns, device model/OS,
signup timing, reused phone/email, repeat signups after a ban.
Low = allow, Medium = extra verification, High = restrict + review.
Flagged users see a clear message with a prominent **Contact Support**
button (copy supplied by the founder). Admin dashboard needs: confidence
score, reasons, approve/reject, and **mark as permanent false positive**
so a legitimate user is not flagged forever. Expect false positives and
design the appeal path first.

## H. MAINTENANCE MODE (#22)

A **maintenance screen** toggled from the web admin dashboard. When on,
**no user can use the app and it cannot be bypassed** — enforcement must
be **server-side**, not a client flag. Users get a notification when it
starts and another when it ends. The founder asked for help designing it.
Note there is already a `/update-required` hard gate and an
`app_config` table used by `ForceUpdateService` — reuse that pattern
rather than inventing a second one.

## I. SMALLER ITEMS

- **#2** Redesign the **composer sheet** (Home → "share something") —
  it was missed in the earlier redesign pass.
  `lib/widgets/home/composer_sheet.dart`.
- **#10** The **search input box** does not look premium — fix it. And
  **add timestamps to post comments**.
- **#11** **Message time = the time it was SENT, not received.** The
  founder wants the WhatsApp behaviour, which is: the bubble and the chat
  list show the **sender's send time**, and messages order by send time —
  so a message sent 10:00 and delivered 11:00 reads **10:00**. Only the
  push notification is tied to delivery.
- **#16** In the **church admin dashboard**, when a super admin
  **rejects** a nominee, the **church admin is not notified**. (The
  nominee path may notify; the nominating admin does not.)

---

# Traps already paid for — don't rediscover them

- **A column-level `REVOKE` is SILENTLY IGNORED when the grant is
  table-level.** It returns success and changes nothing. **UPDATE on
  `profiles` is now per-column: a new profile column is NOT
  client-writable until granted**, and the failure is a swallowed 42501.
  Same for SELECT — a new column is invisible until granted.
- **`suppress_sabbath_notifications()` DROPS** non-essential
  notifications outright during a Sabbath quiet window. Anything that
  must survive belongs in `is_essential_notification`.
- **Scroll notifications from a list inside a `TabBarView` arrive at
  depth 1**, not 0. `NavVisibilityMixin` now filters on **axis**; don't
  put a depth check back.
- **`CrossAxisAlignment.stretch` on a `Row` inside any scrollable** →
  infinite height; in release it paints **nothing**, no red box.
- **`Container(alignment:)` gives LOOSE constraints; `CachedImage` gives
  its errorBuilder TIGHT ones.** Use the shared **`UserAvatar`**.
- **A supabase-dart `.upsert()` needs SELECT *and* UPDATE policies.**
  Missing either → 42501, usually swallowed. Prefer an RPC.
- **Fixed height + wrappable text** is the recurring overflow, and it can
  fail **silently** when no Flex is involved.
- **Curves ending in `…Back` overshoot past 1.0** — assert inside `Opacity`.
- **`notifications` has no client INSERT policy, by design.**
- **Publishing into a shared pool as you build it races with disposal** —
  that is what silenced the quiz. Stage locally, publish once, guard with
  a generation counter.

# Testing rules

- Screens whose `initState` touches Supabase/Hive/the router need a
  constructor seam: `autoLoad` / `autoNavigate` / `autoPrompt` /
  `autoStart`. Seven exist.
- **A field initializer runs before the seam is consulted** — use a getter.
- **Test at 1.0x / 1.6x / 2.5x system text on a 360dp phone.**
- Screens using `StaggeredReveal` need `pumpAndSettle`, not `pump`.
- Widget tests touching `AdBanner` should set
  `PremiumService.debugSet(premium: true)` or the 6s retry loop leaves
  pending timers at teardown.
- **Reproduce before fixing, and let the test correct you.**

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw`;
  **the Bash tool resets cwd between calls.**
- **`python` is NOT installed; `node` v24 is.** **`/tmp` does not exist** —
  use the session scratchpad.
- **CRLF line endings.**
- The Management API `/database/query` returns only the **first** result
  set. Put mutations in a `DO $$ … $$` block.
- **To test against production safely:** work inside a `DO $$ … $$` block
  that `RAISE`s at the end — everything rolls back and the result travels
  out in the error message. Used five times on 3 Aug.
- **Edge functions: deploy via**
  `POST /v1/projects/{ref}/functions/deploy?slug={slug}` as
  **multipart/form-data**, a `metadata` JSON part plus one `file` part
  per file, paths **relative to the repo root**
  (`supabase/functions/<slug>/index.ts`) so `_shared/*.ts` ships too.
  Preserve `verify_jwt` — `notify-fcm` and `play-rtdn` are `false`.
- **Full APK builds are blocked.** Only `flutter analyze`,
  `flutter test`, `flutter build bundle` verify anything. Device builds
  come from CI.
- **The Supabase PAT is not stored anywhere. Ask for it, never write it
  to a file.** The 3 Aug PAT went through chat — **it should be rotated;
  ask whether it was.**

# Still outstanding from before (not in the founder's 22)

- **Finish premium:** create the Play product (ID assumed
  `premium_monthly`, one line in `BillingConfig`), set
  `GOOGLE_PLAY_SA_JSON`, set up Pub/Sub + `RTDN_SECRET`, and run a real
  device purchase. **Money has never been tested.**
- The new analytics RPCs (`admin_feature_usage`,
  `admin_active_users_series`, `admin_platform_breakdown`,
  `admin_premium_stats`) exist and are tested but **nothing calls them
  yet** — they are for the console rebuild. They also only fill once
  users run a build containing the tracking.

---

## Order of work — bugs first, console last

The founder's instruction: **finish the bugs, then build the UI.**

1. The two TURN ONE questions (#7 build check, #6 QR logo).
2. **#20 cross-account data leak** — a security bug and cheap to fix.
3. **#21 biometric leak across accounts** — cause already found.
4. **#4 / #5 premium corrections** — small, and #4 fixes my own mistake.
5. **#3 quiz** — sound, the null-check crash, then agree the multiplayer
   design (A5) with the founder *before* writing any of it.
6. Everything else in the batch.
7. **The admin console — only once the batch is clear.**

Do not silently start the console early. If the batch finishes with time
left, ask before switching.
