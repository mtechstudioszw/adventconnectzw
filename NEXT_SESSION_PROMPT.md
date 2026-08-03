# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (3 Aug 2026, session 2)

All work is pushed. `main` head: **`02b0540`** "Quiz Arena soundtrack
(#3 A2), and a music control now that one is real".

`flutter analyze` clean apart from the **same 4 pre-existing infos**.
**283/283 tests pass** (was 242 at the start of this session, 135 three
sessions ago). No tests are skipped.

**8 of the 22 done, 14 open.** Bug-count-wise better than that sounds:
five of the fixes were for bugs nobody had reported, because every one of
them failed silently.

**NO database changes were made this session.** Everything shipped was
client-side Dart. The production schema is exactly as it was, so there is
nothing new to avoid re-applying.

## Read first

1. `CLAUDE.md` — headers are **FLAT on `palette.scaffoldBg`, never navy**.
2. Memory: `sign-out-must-clear-in-memory-state`, `quiz-arena-decisions`,
   `founder-bug-batch-aug3`, `founder-quality-bar`,
   `motion-must-not-cost-time`, `audio-background-playback-fix`,
   `repo-and-environment`.
3. `git -C adventconnectzw log --oneline -12`

## The rule that keeps paying — repeat it

**Verify the premise before building.** It paid four times this session:
"#6 QR logo" turned out to be an invisible logo rather than a missing one;
the leaderboard the founder wanted was already 90% built; the quiz
"settings button" bug was a control living on a screen that vanishes; and
writing one test for a reported crash uncovered three more bugs that had
never been reported because **all of them failed silently**.

---

# TURN ONE — four things to ask before any code

**1. #3 A1 — does the quiz VIBRATE when you tap an answer?**
This is the whole diagnosis in one question. Haptics are deliberately NOT
gated on the mute toggle (`quiz_sfx.dart`, "Haptics are NOT gated on the
mute toggle"), so:
- **Vibrates but silent** → the call sites fire and `play()` runs. Look at
  device volume, the new Sound & haptics screen, or platform audio.
- **No vibration either** → the call sites are not firing at all, and the
  problem is upstream of `QuizSfx` entirely.

Also ask them to open **Settings → Sound & haptics** in a CI build from
`8293223` or later. If the volume was sitting at 0% that WAS the bug — it
is now floored and self-heals on next launch.

**2. #3 A2 — the soundtrack is BUILT but the audio file is still missing.**
Everything is wired: `QuizMusic` loops for the whole round, stops on
dispose, stands down for the member's own music, and has a toggle +
volume in Settings → Sound & haptics. It just needs the file at

    adventconnectzw/assets/sounds/quiz/arena_loop.mp3

The founder said they downloaded one — **check whether it actually landed
there.** That folder is already declared in `pubspec.yaml`, so no config
change is needed. A missing file is a supported state (the arena runs
silent and sets `QuizMusic.unavailable`), so its absence will not announce
itself — you have to look. Prefer a seamless loop; a track with silence at
the head or tail will gap audibly on every repeat.

**3. The Supabase PAT has now gone through chat twice.** Ask whether it was
rotated. Never write it to a file. Project ref: `eqbyvasteolqyktbqbem`.

**4. #3 A5 — does the EXISTING async challenge system stay?**
The founder chose "pure live head-to-head only" when asked how a match
should work. But `quiz_challenges` already exists, works, and is
async — you play your run, they play theirs, it resolves. The sensible
reading is *add* the live layer and widen challenges beyond friends, NOT
delete something that works. **Confirm before removing anything.**

---

# DONE — do not redo these

| Item | What it actually was |
|---|---|
| **#20** | Statics outlive sign-out. `SessionReset.onSignOut()` is now the one place. |
| **#21** | `biometric_enabled` was one flag per PHONE. Now `biometric_enabled:<userId>`. |
| **#4** | Premium moved into the Profile ⋮ sheet; top-right star deleted. |
| **#5** | Donate + settings copy corrected. A gift is NOT Premium and does not remove ads. |
| **#6** | The QR already had a logo — a WHITE wordmark on a TRANSPARENT background, painted on the code's WHITE plate. Now on a navy disc (`QrCentreMark`). |
| **#3 A4** | The timeout crash fired on EVERY timeout. Fixed + the `autoStart` seam. |
| **#3 A3** | Sound & haptics screen in main settings + settings-search entry. |
| **#3 A2** | `QuizMusic` loop built and wired. Needs only the audio file. |

**Four bugs nobody had reported**, all found while fixing the above:
- The **offline outbox replayed across accounts** — queued rows carry a
  baked-in `sender_id`, RLS rejects them under the new account, and the
  flush loop `break`s on first failure, so one orphaned row **jammed the
  queue permanently** for the next user.
- **`deleteAccount()` never called `CacheService.clearUserData()`** — so
  deleting an account left cached chats and feed on the device.
- **Fix Your Mistakes has never worked.** `addMistake` mutated the
  `const []` that `mistakes()` returns for an empty pool, so it threw on
  the first mistake anyone ever made. Every caller is `unawaited`.
- **`BurstLayer` leaked the whole round screen.** Its Ticker was a lazy
  `late final`, so a round where no burst fired created it inside
  `dispose()`, the TickerMode context lookup threw, and **disposal aborted
  part-way** — leaving the round's timer and four controllers alive.

---

# THE REMAINING BATCH — 14 items

## A. QUIZ — what is left (#3)

### A1. Sound — see TURN ONE question 1
Assets are fine and were verified this session: all nine WAVs are valid
PCM mono 16-bit / 22.05 kHz with clean `fmt `+`data` chunks, and
`assets/sounds/quiz/` is declared in `pubspec.yaml`. The code path is
correct end to end and `play()` self-heals when the pool is down. Two real
faults were found and fixed (the 0% volume latch; controls only reachable
during the ~900ms boot flash). If it is still silent after that, it is
device/platform and needs the vibrate answer plus a `flutter logs` line
starting `QuizSfx.init failed:` — that call catches everything and only
`debugPrint`s, so a boot failure is otherwise invisible.

### A2. Background music — BUILT, waiting only on the audio file
`lib/services/quiz_music.dart`. Loops for the round, stopped in the round
screen's `dispose()` so it ends by any exit route. Deliberately built on
**audioplayers, not just_audio** — the Library player owns the app's
just_audio instance and its media session, and staying in a different
package means the loop cannot touch it. `MusicPlayerService.isPlayingNow`
was added for the ducking check and reads `_player` DIRECTLY: the public
`player` getter constructs the player, and creating one just to ask a
yes/no question is how background playback broke three times.

Left to do once the file lands: confirm it loops without an audible gap,
and decide whether it should pause when the app is backgrounded (it
currently keeps looping, which is right for a quick alt-tab and wrong for
a long one).

### A5. Live head-to-head — DESIGN AGREED, NOT BUILT

**The founder's four decisions. Do not re-litigate:**
1. **Pure live head-to-head only** (I recommended async-first; they chose
   live. Settled — build it.) Mitigate *within* that decision: drive
   matchmaking off `PresenceService`'s online roster so you challenge
   people who are actually online, and show an honest "nobody available
   right now" instead of an endless spinner.
2. Quiz profile **optional for solo play, required for leaderboard and
   challenges**.
3. Leaderboard ranks **weekly points that RESET** — not Elo, not all-time.
4. Challenge notifications **stay suppressed** during Sabbath quiet hours.

**Production schema surveyed this session — what already exists:**
- `quiz_challenges` — id, challenger_id, opponent_id, questions jsonb,
  challenger_points/correct, opponent_points/correct, status, created_at,
  completed_at, expires_at. **This is a working async challenge system**,
  currently friends-only (`QuizOpponent` = "A friend you can challenge").
- `quiz_progress` — xp, streaks, totals, lifetime_points, coins.
- `quiz_questions` — the bank. `quiz_reports`. 
- `quiz_scores` — user_id, mode, points, correct_count, total_count,
  **played_at**.
- **`quiz_leaderboard(p_days, p_limit)` already exists** and is already
  weekly: it sums `quiz_scores` over a ROLLING `now() - p_days`. The only
  gap vs the founder's choice is that it rolls (your score silently decays
  as rounds age out) instead of resetting on a fixed weekly boundary.
  `quiz_my_rank(p_days)` exists too.
- **Does NOT exist:** `quiz_profiles`, and any live-match tables.

**Still to build:** `quiz_profiles` (display name + photo, gates
leaderboard/challenges), `quiz_matches`, `quiz_match_answers`, the RPCs,
and the leaderboard's rolling→resetting change plus using the quiz
identity instead of `profiles.full_name`.

**Constraints the founder explicitly asked to be designed for:**
1. **Server-authoritative timing.** The match row carries
   `question_started_at` from the server; each client counts down from
   that, never from packet arrival, or a 300ms slower connection silently
   loses every race.
2. **Never ship `correct_index` to the client before the answer locks.**
   It is on the client today (`_question.correctIndex`) — fine solo, fatal
   competitively.
3. **Score on the server.** Submit via an RPC that stamps arrival time and
   returns only "locked"; reveal once both have answered or time expired.
4. **Disconnect / rage-quit must forfeit**, never hang the opponent.
5. **Reconnect mid-match** — rejoin and catch up to the current index.
6. **The Realtime channel carries the same publish/dispose race** that
   silenced the quiz. Guard with a generation counter.
7. Timeout = wrong answer, consistent with solo.

## B. ADS (#7) — NEW SYMPTOM, REPRODUCE FIRST

**Premise confirmed the hard way:** the founder DID install a build from
`c3e06d6` or later and the Events/Churches banner **still takes the full
screen**. So the shipped fix is not the fix. Do not re-fix blind —
reproduce it. Full APK builds are blocked here; device builds come from CI
(`.github/workflows/build-apk.yml`).

Related: `lib/widgets/ads/scroll_aware_ad_footer.dart` is built and tested
but **still not used anywhere**. It exists so the reverted detail-screen
placements (commits `c18cd7f` → `13d55c0`) can come back safely.

**Ad revenue expansion** (founder wants it — build only what they pick):
restore product/event/church detail + seller storefront; then search
results, Advent News, notification centre, member directory; Library browse
needs a faith call (**recommend no ads in the Bible reader**); highest
value is **more rewarded ads** (currently only quiz lifelines), e.g. "watch
an ad to boost your listing 24h". **Never**: Chat, auth, Prayer, and never
for premium users — those exclusions are verified correct.

## C. PLAYERS / MINI-PLAYERS (#8, #9)

**Music (#8):** full player must hide the mini player and restore it on
exit; mini player draggable to top/middle/bottom; closing it must **stop
playback immediately**; **shuffle does not work**; **download-for-offline
does not work**; its shape is wrong — a long horizontal bar where it should
read like a small video card.

**Watch (#9):** same hide/show rule; make it a real YouTube-style floating
player, draggable and resizable with video playing inside; **remove the
follow button**.

Beware [[audio-background-playback-fix]].

## D. HOME / FEED (#1, #13, #14)

- **#1** Devotion card clips the verse — **ellipsize**. And **Verse of the
  Day** should open the Bible **scrolled to and highlighting that verse**.
- **#13** Two rows of "People to meet", surfaced at different times. They
  also asked whether the feed can scroll endlessly — at 170 users the
  honest answer is recycle/blend rather than fake infinite. Say so.
- **#14** Make the feed algorithmic so modules reliably reappear. See
  memory `feed-ranking-findings` for how ranking works today.

## E. PROFILE / ACCOUNT

- **#12** Cache the profile screen (friends list etc.), then audit other
  screens that refetch on every visit.
- **#15** Edit Profile says "Full name" but signup collects name + surname.
- **#17** Delete account and sign out must feel **instant**. See
  [[motion-must-not-cost-time]].
- **#18** Exit-survey screen on account deletion; store the reason and
  surface it in the web admin dashboard.
- **#19** The "how did you hear about us" survey no longer appears on first
  signup. `SignupSurveySheet` exists at
  `lib/widgets/home/signup_survey_sheet.dart`, called from `home_screen`
  after ~1200ms, gated by `SignupSurveyService.shouldPrompt()` — **check
  that gate first.** patch_180 records that every non-admin submit used to
  fail. Confirm the 6s premium promo isn't swallowing it (it should not —
  the promo refuses when another sheet is up).

## F. BAN-EVASION DETECTION (#21, the feature half)

Risk **scoring**, never a single identifier: device install id, push token,
IP patterns, device model/OS, signup timing, reused phone/email, repeat
signups after a ban. Low = allow, Medium = extra verification, High =
restrict + review. Flagged users get a clear message with a prominent
**Contact Support** button. Admin dashboard needs confidence score,
reasons, approve/reject, and **mark as permanent false positive**. Expect
false positives and design the appeal path first.

## G. MAINTENANCE MODE (#22)

Toggled from the web admin dashboard. When on, **no user can use the app
and it cannot be bypassed** — enforcement must be **server-side**. Users
get a notification when it starts and another when it ends. There is
already a `/update-required` hard gate and an `app_config` table used by
`ForceUpdateService` — **reuse that pattern**, do not invent a second one.

## H. SMALLER ITEMS

- **#2** Redesign the composer sheet (Home → "share something") —
  `lib/widgets/home/composer_sheet.dart`. Missed in the earlier pass.
- **#10** The search input box does not look premium. Also **add timestamps
  to post comments**.
- **#11** Message time = the time it was **SENT**, not received. WhatsApp
  behaviour: bubble and chat list show the sender's send time, and
  messages order by send time. Only the push is tied to delivery.
- **#16** In the church admin dashboard, when a super admin **rejects** a
  nominee the **church admin is not notified**. (The nominee path may
  notify; the nominating admin does not.)

---

# WEB ADMIN DASHBOARD — DECIDED, still DEFERRED

**Founder's call: "I will build UI soon after all bugs are finished."**
Do NOT start it. Clear the batch first, then ask.

Settled, do not re-litigate: **web admin only**; **`admin-web/` is the app
in real use** (git proves it) and is the thing being replaced; **stack is
Next.js in `admin/`** (App Router, auth middleware, server actions and
Tailwind already there); **deploy to Vercel**, founder connects the repo
themselves with publish root `admin/`. Migrate everything `admin-web/` has
that `admin/` lacks — 14 tabs vs 7. **Do not delete `admin-web/`** until
the replacement is deployed and signed off; it is their only console today.

Backend already built, live, attack-tested, but **called by no UI yet**:
`admin_feature_usage`, `admin_active_users_series`,
`admin_platform_breakdown`, `admin_premium_stats`; and staff roles + audit
log (`viewer` / `moderator` / `manager` / `owner`, with
`assert_staff('moderator')` and `log_admin_action(...)` for new work).
People/Settings should manage staff via `admin_list_staff()` /
`admin_set_staff_role()` — nobody should set `is_super_admin` by hand.

**No data source, do not promise:** crash reporting (Firebase), ad
impressions/CTR/eCPM (AdMob), country/city, session duration, retention
cohorts, infrastructure metrics.

---

# Traps already paid for — don't rediscover them

**New this session:**
- **A lazy `late final` ticker/controller is CREATED during `dispose()`**
  if nothing touched it first, and its context lookup then throws
  *"Looking up a deactivated widget's ancestor"* — which **aborts disposal
  part-way**, silently leaking everything after it. `AnimationController`
  calls `createTicker` in its constructor, so `late final
  AnimationController _c = ...` has the same hazard. Build them in
  `initState`. ~12 such fields exist; the rest are safe only because
  `build()` touches them first.
- **`CacheService.clearUserData()` spares the whole `pref:` namespace** so
  device settings survive sign-out. Any USER-scoped `pref:` key therefore
  leaks to the next account. Namespace by user id — the good example
  already in the tree is `pref:viewed_story_ids:<viewerId>`.
- **Signing out does not restart the Dart isolate.** Every `static`
  outlives it. Reset user-scoped state in `SessionReset.onSignOut()`, never
  in a sign-out button — there are three of those and they each used to do
  a different subset.
- **`mounted` is not a sufficient guard during teardown.** While the tree
  is being finalized an element is deactivated but `mounted` still reads
  true. Use a cancellable `Timer` cancelled in `dispose()`, not
  `await Future.delayed(...)` followed by a `mounted` check.
- **Returning `const []` from a getter whose callers mutate it** throws
  *"Cannot remove from an unmodifiable list"* — and only on the empty path,
  which is the FIRST call. `List.of()` at the mutation site.
- **`testWidgets(skip:)` takes a bool**, not a String reason.
- **The Bash tool resets cwd between calls** — this bit twice. Use
  `cd /c/Users/j/Desktop/advent_connect_zw/adventconnectzw && …`.

**Still true from before:**
- **A column-level `REVOKE` is SILENTLY IGNORED when the grant is
  table-level.** UPDATE on `profiles` is per-column: a new column is NOT
  client-writable until granted, and the failure is a swallowed 42501.
  Same for SELECT.
- **`suppress_sabbath_notifications()` DROPS** non-essential notifications
  during a quiet window. Anything that must survive belongs in
  `is_essential_notification`.
- **Scroll notifications from a list inside a `TabBarView` arrive at depth
  1**, not 0. `NavVisibilityMixin` filters on **axis** — don't put a depth
  check back.
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
  stage locally, publish once, guard with a generation counter.

# Testing rules

- Screens whose `initState` touches Supabase/Hive/the router need a
  constructor seam: `autoLoad` / `autoNavigate` / `autoPrompt` /
  `autoStart`. **Eight exist now** — `QuizRoundScreen` gained one.
- **A field initializer runs before the seam is consulted** — use a getter,
  or assign in `initState`.
- **Test at 1.0x / 1.6x / 2.5x system text on a 360dp phone.**
- Screens using `StaggeredReveal` need `pumpAndSettle`, not `pump`.
- Widget tests touching `AdBanner` should set
  `PremiumService.debugSet(premium: true)` or the 6s retry loop leaves
  pending timers at teardown.
- To drive a long animation, **pump in small steps**, not one big jump — a
  jump trips `AnimationController`'s own `elapsedInSeconds >= 0.0` assert.
- **Reproduce before fixing, and let the test correct you.** This session
  that turned one reported crash into four fixed bugs.

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw`;
  **the Bash tool resets cwd between calls.**
- **`python` is NOT installed; `node` v24 is.** **`/tmp` does not exist** —
  use the session scratchpad. (node is genuinely useful: it decoded the PNG
  that proved the QR logo was transparent, and parsed the WAV headers.)
- **CRLF line endings.**
- The Management API `/database/query` returns only the **first** result
  set. Put mutations in a `DO $$ … $$` block.
- **To test against production safely:** work inside a `DO $$ … $$` block
  that `RAISE`s at the end — everything rolls back and the result travels
  out in the error message.
- **Edge functions: deploy via**
  `POST /v1/projects/{ref}/functions/deploy?slug={slug}` as
  **multipart/form-data**, a `metadata` JSON part plus one `file` part per
  file, paths **relative to the repo root** so `_shared/*.ts` ships too.
  Preserve `verify_jwt` — `notify-fcm` and `play-rtdn` are `false`.
- **Full APK builds are blocked.** Only `flutter analyze`, `flutter test`
  and `flutter build bundle` verify anything. Device builds come from CI.
- **The Supabase PAT is not stored anywhere. Ask for it, never write it to
  a file.**

# Still outstanding from before (not in the founder's 22)

- **Finish premium:** create the Play product (ID assumed
  `premium_monthly`, one line in `BillingConfig`), set `GOOGLE_PLAY_SA_JSON`,
  set up Pub/Sub + `RTDN_SECRET`, and run a real device purchase.
  **Money has never been tested.**
- The analytics RPCs exist and are tested but **nothing calls them yet** —
  they are for the console rebuild, and they only fill once users run a
  build containing the tracking.

---

## Order of work

1. The four TURN ONE questions.
2. **#3 A5 live multiplayer** — the big remaining piece, and the first
   thing needing the PAT.
3. **#7 ads** — reproduce the full-screen banner before touching it.
4. **#11, #15, #16, #1, #10** — small and well-specified.
5. **#8 / #9 players** — large, and audio is the most fragile area here.
6. **#12, #13, #14, #17, #18, #19, #2, #22** and ban-evasion.
7. **The admin console — only once the batch is clear.** Do not start it
   early; if the batch finishes with time left, ask.
