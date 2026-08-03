# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (3 Aug 2026, session 3)

**18 of the 22 done. 6 open: #2, #13, #14, #8, #9, and ban-evasion.**

`flutter analyze` clean apart from the **same 4 pre-existing infos**.

**Nothing is committed.** Every change from this session is in the working
tree. First job: review `git -C adventconnectzw status`, then commit and
push so CI can build an APK — the founder needs a device build to test the
live multiplayer, the ad-banner fix and the quiz sound.

**Tests were written but NOT RUN.** `flutter test` takes >10 minutes on this
machine and the founder interrupted a run. Three new test files need one CI
run: `test/ad_banner_height_test.dart`,
`test/sound_settings_persistence_test.dart`, `test/bible_reference_test.dart`.
Verify with `flutter analyze` during a session, never `flutter test`.

## Read first

1. `CLAUDE.md` — headers are **FLAT on `palette.scaffoldBg`, never navy**.
2. Memory: `quiz-live-multiplayer`, `ad-banner-center-trap`,
   `settings-read-unloaded-statics`, `flutter-test-too-slow-here`,
   `founder-bug-batch-aug3`, `founder-quality-bar`,
   `motion-must-not-cost-time`, `audio-background-playback-fix`.
3. `git -C adventconnectzw log --oneline -12`

## The rule that keeps paying — repeat it

**Verify the premise before building.** It paid five times this session:

- **#3 A2** — the soundtrack was not missing. It was on disk as
  `arena_loop.mp3.**mpeg**`. A double extension, and a missing asset is a
  supported silent state, so it never announced itself.
- **#7** — the shipped `HideOnScroll` fix made a full-height bar
  *collapsible*, which read as progress. The bar was full height because a
  bare `Center` does not shrink-wrap under `bottomNavigationBar`'s
  loose-but-bounded constraints.
- **#10** — the main search field had already been redesigned. What was
  actually cheap-looking was a 45-character hint truncating mid-word in a
  ~230dp box.
- **#1** — the devotion verse already had `maxLines` + ellipsis. The fixed
  224px height was clipping it, and `Text` does not drop lines to fit.
- **#19** — **not a bug.** Since patch_180, 3 of 3 signups have answered.
  The founder cannot see it because their account is older than the
  deliberate 14-day window. **Do not "fix" this.**

---

# DB patches applied this session

All applied to production and verified. **Do not re-apply.**

| Patch | What |
|---|---|
| **183** | `quiz_profiles`, `quiz_matches`, `quiz_match_keys`, `quiz_match_answers`, all live-match RPCs, resetting weekly leaderboard |
| **184** | `messages.sent_at` + clamp trigger + `my_inbox_previews` rewrite |
| **185** | `notify_church_admin_status` also notifies the nominating primary admin |
| **186** | `account_deletion_surveys` + `admin_deletion_reasons` |
| **187** | Maintenance mode: `maintenance_active()`, `admin_set_maintenance()`, 26 `maintenance_block` triggers |

**Production maintenance mode is OFF** (`app_config.maintenance_mode = '0'`).
Confirmed after testing.

---

# THE REMAINING BATCH — 6 items

## #8 / #9 — PLAYERS (large, and the most fragile area here)

**Music (#8):** full player must hide the mini player and restore it on
exit; mini player draggable to top/middle/bottom; closing it must **stop
playback immediately**; **shuffle does not work**; **download-for-offline
does not work**; its shape is wrong — a long horizontal bar where it should
read like a small video card.

**Watch (#9):** same hide/show rule; a real YouTube-style floating player,
draggable and resizable with video playing inside; **remove the follow
button**.

Beware `audio-background-playback-fix`: `PlayerMode.mediaPlayer` (not
lowLatency) and `AndroidAudioFocus.none` are deliberate. Never swap the
platform instance — that has killed background playback three times.

## #13 / #14 — HOME / FEED

- **#13** Two rows of "People to meet", surfaced at different times. They
  also asked whether the feed can scroll endlessly — at 171 users the
  honest answer is recycle/blend, not fake infinite. **Say so.**
- **#14** Make the feed algorithmic so modules reliably reappear. See
  memory `feed-ranking-findings`.

## #2 — COMPOSER SHEET

Redesign Home → "share something": `lib/widgets/home/composer_sheet.dart`.

## BAN-EVASION DETECTION (#21, the feature half)

Risk **scoring**, never a single identifier: device install id, push token,
IP patterns, device model/OS, signup timing, reused phone/email, repeat
signups after a ban. Low = allow, Medium = extra verification, High =
restrict + review. Flagged users get a clear message with a prominent
**Contact Support** button. Admin dashboard needs confidence score, reasons,
approve/reject, and **mark as permanent false positive**. Expect false
positives and design the appeal path first.

---

# WEB ADMIN DASHBOARD — still DEFERRED

**Founder: "I will build UI soon after all bugs are finished."** Clear the
six above first, then ask.

New backend built this session that the console will need:
`admin_set_maintenance(bool, text, timestamptz)` — needs an owner-role
toggle with a message + optional end time — and
`admin_deletion_reasons(p_days)` for the #18 exit-survey chart.

Settled, do not re-litigate: **web admin only**; **`admin-web/` is the app
in real use** and is what is being replaced; **stack is Next.js in
`admin/`**; **deploy to Vercel**. **Do not delete `admin-web/`** until the
replacement is signed off.

---

# Traps already paid for — don't rediscover them

**New this session:**
- **A bare `Center` only shrink-wraps when constraints are UNBOUNDED.**
  `Scaffold` gives `bottomNavigationBar` a LOOSE constraint whose max is the
  whole screen — loose is still bounded, so `Center` takes all of it. Use
  `heightFactor: 1`. See `ad-banner-center-trap`.
- **A settings screen that reads a static nothing has loaded shows
  defaults, convincingly.** `QuizSfx` loaded prefs only inside `init()`.
  Getters must load on read.
- **`authenticated` arrives holding table-level GRANT ALL on new public
  tables.** Only the absence of a policy stops writes. `REVOKE ALL` then
  grant back explicitly.
- **`CREATE OR REPLACE FUNCTION` refuses a changed `RETURNS TABLE`.** Drop
  first (this bit `my_inbox_previews`).
- **`log_admin_action` takes SIX arguments.** Pass them all.
- **The Management API mangles `''` escaping** inside a shell-quoted JSON
  payload. Write the query to a scratchpad file and use `-d @file`.

**Still true from before:**
- **A column-level `REVOKE` is SILENTLY IGNORED when the grant is
  table-level.**
- **`suppress_sabbath_notifications()` DROPS** non-essential notifications
  during a quiet window. `maintenance` was added to
  `is_essential_notification` for exactly this reason.
- **A lazy `late final` ticker/controller is CREATED during `dispose()`**
  and aborts disposal part-way. Build them in `initState`.
- **`mounted` is not a sufficient guard during teardown.** Use a cancellable
  `Timer`.
- **`CrossAxisAlignment.stretch` on a `Row` inside any scrollable** →
  infinite height; in release it paints **nothing**.
- **A supabase-dart `.upsert()` needs SELECT *and* UPDATE policies.**
- **Publishing into a shared pool as you build it races with disposal** —
  stage locally, publish once, guard with a generation counter.
- **The Bash tool resets cwd between calls.** Use
  `cd /c/Users/j/Desktop/advent_connect_zw/adventconnectzw && …`.

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw`.
- **`python` is NOT installed; `node` v24 is.** **`/tmp` does not exist** —
  use the session scratchpad.
- **CRLF line endings.**
- The Management API `/database/query` returns only the **first** result
  set. Put mutations in a `DO $$ … $$` block.
- **To test against production safely:** work inside a `DO $$ … $$` block
  that `RAISE`s at the end — everything rolls back and the result travels
  out in the error message. Used five times this session.
- **Full APK builds are blocked.** Device builds come from CI
  (`.github/workflows/build-apk.yml`).
- **The Supabase PAT is not stored anywhere. Ask for it, never write it to
  a file.** Project ref `eqbyvasteolqyktbqbem`. It has now gone through chat
  three times and should be rotated again.

# Still outstanding from before (not in the founder's 22)

- **Finish premium:** create the Play product (`premium_monthly`), set
  `GOOGLE_PLAY_SA_JSON`, set up Pub/Sub + `RTDN_SECRET`, run a real device
  purchase. **Money has never been tested.**
- The analytics RPCs exist and are tested but **nothing calls them yet**.

---

## Order of work

1. Commit + push this session's work so CI can build.
2. **#8 / #9 players** — large, and audio is the most fragile area here.
3. **#13 / #14** feed.
4. **#2** composer sheet.
5. **Ban-evasion.**
6. **The admin console — only once the batch is clear.** Ask first.
