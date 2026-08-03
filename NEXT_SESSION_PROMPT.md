# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (3 Aug 2026, session 4)

**The founder's 22-item batch is CLEAR.** #2, #8, #9, #13 and #14 all shipped
this session. Nothing from the batch is outstanding.

**Everything is committed AND pushed.** `main` == `origin/main`. Four commits
this session:

| Commit | What |
|---|---|
| `d06d43b` | #8 / #9 — the players float |
| `a03d1d9` | #13 / #14 — people rails + feed ordering |
| `7f9db65` | #2 — composer sheet |
| _(this file)_ | handoff |

CI builds a debug APK on every push to `main` and publishes it to the
**Latest debug build** release. `flutter analyze` clean apart from the **same
4 pre-existing infos**.

## Two things the founder decided at the end of session 4

1. **Ban-evasion is DEFERRED entirely.** Not started. See the section below
   for what the premise check found — it is bigger than the brief assumed.
2. **The admin console is NOT started yet.** The founder wants to test the
   new APK on a device first. Bugs found there jump the queue.

**So the next session starts by asking what the device test found.**

---

# THE RULE THAT KEEPS PAYING — repeat it

**Verify the premise before building.** Session 3 turned five "build this"
items into "already built" or "actually a different bug". Session 4 did it
four more times:

- **"Nothing is committed"** — it was all committed *and* pushed. `main` and
  `origin/main` were both at `3de9a2c`, clean tree, no stash. The three
  "never run" test files had already run in CI too: `build-apk.yml` does
  analyze → test → build → release, so a red test never reaches the release
  step.
- **#8 "shuffle does not work"** — real, and broken **three** ways at once.
  See below.
- **#8 "download-for-offline does not work"** — the download code was fine.
  **Sign-out was deleting the index.**
- **#8 "hide the mini player when the full player opens"** — already built
  and working, for both music and Watch. Left alone.

---

# What shipped in session 4

## #8 / #9 — the players

**Shuffle** was broken three separate ways simultaneously: the Music tab
loaded the queue at index 0 so Shuffle always opened on the same track;
`player.shuffle()` **pins the current item to the front** of the new order,
so track 0 led the shuffled order too; and it only shuffled
`if (!shuffleModeEnabled)`, so a second press reused the old order.
`MusicPlayerService.shuffleAll` picks the start at random and re-deals
unconditionally, which turns the pinning into an advantage.

**Downloads** — `CacheService.clearUserData()` deletes every key that does
not start with `pref:`, and it runs on every sign-out. The index was a bare
`music_downloads_v1`. Files stayed on disk, orphaned and invisible; the
Downloaded filter went to zero and playback reverted to streaming. Index is
now `pref:`-prefixed, the old key is read once, and startup **re-adopts
orphaned files**. Playback speed had the same bug. Likes / history /
playlists / resume-queue stay unprefixed **on purpose** — personal, and a
shared phone must not hand them to the next account.

**Both players are draggable.** One `FloatingDock`
(`lib/widgets/media/floating_dock.dart`) carries the physics: the music card
parks top/middle/bottom, the Watch window parks in a corner and resizes.
The music mini is a **card** now, not a full-width bar. The Watch mini is a
real 16:9 floating window with the live embed inside.

Follow button removed from the video screen, along with the subscription
round-trip only it needed.

## #13 / #14 — home / feed

**#14 was one line.** `_buildDiscoveryCards()` sorts modules by onboarding
interest and a per-viewer seed — and `_buildFeedChildren` then re-shuffled
the result, throwing it away. The shuffle was seeded so it looked
deliberate; what it meant was that onboarding interests did nothing.

**The other half of #14 was pacing.** One card every five posts is right for
a full feed. With this backlog it meant one module interleaved and the rest
stacked below the last post where nobody scrolls. Spacing now derives from
the actual post count, capped at the old five.

**#13** — two people rails at different depths, drawing from disjoint slices
of an 18-person pool. The second does not build unless it has 3+ people.
Slots can declare a `_SlotDepth`, and depth outranks interest weighting.

**Endless scroll — the answer given:** the feed already pages properly
(keyset cursor, auto-loads 900px from the bottom) and stops with "You're all
caught up". It does **not** recycle read posts and should not — at this size
that is obvious within one scroll. The end-of-feed card now offers *Meet
people* and *Events* instead of being a dead end.

## #2 — composer

The sheet never said **who** was posting — and the same sheet publishes AS A
CHURCH when opened from a church page. Identity row (avatar, name, audience
under the name; gold tick + "Church update · everyone" for churches),
borderless larger field, tonal toolbar chips, and the autosaved draft now
announces itself with a *Start fresh* escape.

---

# BAN-EVASION — DEFERRED, and the premise check that matters

**Do not start this without re-reading this section.** The brief assumes
more infrastructure than exists.

- **A ban is a single boolean, `profiles.is_banned`.** There is no ban
  ledger — no who, when, why, or by whom. `database/schema.sql:86`.
- **The app collects NO device signals at all.** No `device_info_plus`, no
  `package_info_plus`, no install id, nothing. Verified against `pubspec.yaml`
  and all of `lib/`.
- **Therefore detection is retroactive-blind.** A new signup can only be
  matched against signals that were *already being recorded* before the ban.
  Everyone banned to date has no fingerprint and will never be caught by
  this. The feature's value starts on ship day.
- **It is privacy-sensitive.** Collecting device identifiers changes the
  Play Store data-safety declaration.

Recommended staging when it is picked up: **signal collection + a real ban
ledger first**, so the clock starts; scoring, the restricted-user screen with
**Contact Support**, and the admin review queue on top of real data
afterwards. Thresholds tuned against zero data are guesswork.

Design constraints from the founder that still stand: risk **scoring**, never
a single identifier; Low = allow, Medium = extra verification, High =
restrict + review; admin dashboard needs confidence score, reasons,
approve/reject and **mark as permanent false positive**; expect false
positives and **design the appeal path first**.

---

# WEB ADMIN DASHBOARD — still not started

Founder, end of session 4: **test the APK on a device first.** Ask what the
device test found before proposing a start date.

Settled, do not re-litigate: **web admin only**; **`admin-web/` is the app in
real use** and is what is being replaced; **stack is Next.js in `admin/`**;
**deploy to Vercel**; **do not delete `admin-web/`** until the replacement is
signed off.

Backend the console will need that already exists:
`admin_set_maintenance(bool, text, timestamptz)` (owner-role toggle with a
message + optional end time) and `admin_deletion_reasons(p_days)` for the #18
exit-survey chart.

---

# DB patches — 183 to 187 are APPLIED. Do not re-apply.

183 quiz live matches · 184 `messages.sent_at` · 185 notify nominating admin ·
186 deletion exit survey · 187 maintenance mode.

**Production maintenance mode is OFF** (`app_config.maintenance_mode = '0'`).
Leave it off.

**No DB changes were made in session 4.** Production schema is untouched.

---

# Tests

**`flutter test` is only slow with NO ARGUMENTS.** Named files are fast —
three files / 12 tests ran in **5 seconds** this session. Run the files you
touched, by path, every time. Never run the bare suite; let CI do that.

New this session: `test/floating_dock_test.dart`,
`test/music_downloads_survive_signout_test.dart`. Both pass, along with
`test/composer_sheet_test.dart` (which caught two real breakages in the
composer redesign — an unguarded `AuthService.currentUser` and a Row that
would overflow at 2.5x text scale).

Session 3's three files — `ad_banner_height_test`,
`sound_settings_persistence_test`, `bible_reference_test` — went green in CI
on the `3de9a2c` push.

---

# Traps already paid for — don't rediscover them

**New in session 4:**
- **`CacheService.writePref` does NOT add the `pref:` prefix for you.** The
  key must literally start with `pref:` or sign-out deletes it. This has now
  bitten the quiz sound settings AND the music downloads index.
- **`player.shuffle()` pins the CURRENT track to the front** of the new
  order. Loading at index 0 and then shuffling gives you index 0 first,
  every time.
- **`AuthService.currentUser` reaches through `Supabase.instance`**, which
  **throws** when the client is not initialised. Guard it in any widget that
  a test might pump.
- **A `Row` whose labels scale with the system font throws** rather than
  clipping. Use `Wrap` on toolbars.
- **`Align`/`Center` shrink-wrap only under UNBOUNDED constraints.** Still
  true, still the ad-banner trap; `FloatingDock` avoids it by placing its
  child at an explicit size inside an explicit `Positioned`.
- **A WebView reloads if re-parented** — the Watch window drags the box, not
  the player.

**Still true from before:** column-level `REVOKE` is silently ignored against
a table-level grant · `suppress_sabbath_notifications()` DROPS non-essential
notifications in a quiet window · a lazy `late final` controller is CREATED
during `dispose()` · `mounted` is not sufficient during teardown, use a
cancellable `Timer` · `CrossAxisAlignment.stretch` on a `Row` in a scrollable
paints nothing in release · `.upsert()` needs SELECT *and* UPDATE policies ·
publishing into a shared pool as you build it races with disposal ·
`CREATE OR REPLACE FUNCTION` refuses a changed `RETURNS TABLE` ·
`log_admin_action` takes SIX arguments · the Management API mangles `''`
escaping, use `-d @file`.

---

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw`.
- **The Bash tool is bash, not PowerShell.** `@'...'@` here-strings are a
  syntax error there. For commit messages write the text to the scratchpad
  and use `git commit -F <file>`.
- **`python` is NOT installed; `node` v24 is.** **`/tmp` does not exist** —
  use the session scratchpad.
- **`gh` CLI is NOT installed**, and the repo is private, so CI status cannot
  be read from a session. Check the Actions tab / Releases page manually.
- **CRLF line endings.**
- The Management API `/database/query` returns only the **first** result set.
  Put mutations in a `DO $$ … $$` block. To test against production safely,
  work inside a `DO $$ … $$` that `RAISE`s at the end — everything rolls back
  and the result travels out in the error message.
- **Full APK builds are blocked locally.** Device builds come from CI
  (`.github/workflows/build-apk.yml`).
- **The Supabase PAT is not stored anywhere. Ask for it, never write it to a
  file.** Project ref `eqbyvasteolqyktbqbem`. It has now gone through chat
  **four** times and should be rotated.

# Still outstanding from before (not in the founder's 22)

- **Finish premium:** create the Play product (`premium_monthly`), set
  `GOOGLE_PLAY_SA_JSON`, set up Pub/Sub + `RTDN_SECRET`, run a real device
  purchase. **Money has never been tested.**
- The analytics RPCs exist and are tested but **nothing calls them yet**.

---

## Order of work

1. **Ask what the device test of the new APK found.** Fix anything it turned
   up — that jumps the queue.
2. Then ask again about the admin console.
3. Ban-evasion, if the founder wants it, staged as above.
