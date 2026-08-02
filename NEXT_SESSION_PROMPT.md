# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (29 Jul 2026)

All work is pushed. `main` head: **`Profile setup joins the shared
first-run backdrop`**. `flutter analyze` is clean apart from **4
pre-existing infos** in files nobody touched; **38/38 tests pass**.
Migrations **178–182 are applied to production and verified** — do NOT
re-apply them.

The 29 Jul session closed out **every reported bug (25 of them)** and
started the redesign backlog. What remains is redesign work plus one
feature.

## Do this before writing any code

1. Read `CLAUDE.md`. It was corrected on 29 Jul — the colour table used
   to say Dark Navy was for "Headers, app bar", which is the *opposite*
   of the rule twenty lines below it. **Headers are FLAT on
   `palette.scaffoldBg`, never navy.** Account screens use `AuthShell`;
   Home's Sabbath header is flat with a sundown wash + gold horizon.
2. Read the memory files `bug-round-jul29` and `open-backlog-jul29`.
3. `git -C adventconnectzw log --oneline -12`.

## Remaining work, in the order I'd take it

### 1. Finish the first-run path — 2 screens
`AuthShell` (`lib/screens/auth/widgets/auth_shell.dart`) already frames
forgot-password and email-verification; profile-setup shares its ambient
backdrop. Still to do:

- **`lib/screens/splash/biometric_lock_screen.dart`** → move onto
  `AuthShell` with `onBack: null`. A locked screen must not offer a way
  out; the shell handles that case and it is covered by
  `test/auth_shell_test.dart`.
- **`lib/screens/splash/splash_screen.dart`** → give it the same
  `AmbientPainter` backdrop so cold start → intro → auth is one piece.

**Rule:** a screen on `AuthShell` must NOT add its own entrance
controller — the shell owns the staggered rise. Two screens had their
own; both were deleted.

### 2. Remaining redesigns
Founder's bar: premium, "not cheap or vibe coded", real motion.

- **Search screen** (`lib/screens/home/search_screen.dart`). The search
  *bug* is already fixed (patch_179 `search_profiles` RPC — per-word
  matching + pg_trgm fuzzy over full_name AND username). This is purely
  visual.
- **Home share/create sheet** — "the screen that comes when you click
  share". `lib/widgets/home/create_sheet.dart` / `composer_sheet.dart`.
- **Chat settings** (three-dots → chat settings) + new features.
- **Church profile screen** — circular profile picture and a
  background/cover, both sized so an admin's upload *just fits* the
  space. Mind the loose-constraints trap below; that is exactly what
  left white edges around the profile avatar.

### 3. The one remaining FEATURE
**Announcement reactions.** Members react to church announcements; the
admin sees reaction analytics in the dashboard; church admins get a
notification (persisted) when someone reacts. Needs a migration.

Build on what exists: `announcement_reads` (patch_173),
`church_announcement_reach()`, and `nudge_profile_incomplete()`
(patch_181) as the pattern for a SECURITY DEFINER notification writer —
`notifications` has **no client INSERT policy**, by design.

## Traps that already cost real time — do not rediscover these

- **`CrossAxisAlignment.stretch` on a `Row` inside any scrollable is
  always a bug.** It passes the Row's unbounded cross-axis extent to
  children as a TIGHT constraint → "BoxConstraints forces an infinite
  height" → in release the widget paints **nothing**: a blank grey area,
  no red error box. This is what made the entire Prayer screen look
  empty while the backend was provably fine.
- **A supabase-dart `.upsert()` is `INSERT … ON CONFLICT DO UPDATE …
  RETURNING`.** So the table needs **SELECT *and* UPDATE** policies, not
  just INSERT. Missing either → 42501, usually swallowed by a `catch`.
  This bit three times (`signup_surveys`, `story_likes`,
  `youtube_subscriptions`). If the row is a pure membership tuple, pass
  `ignoreDuplicates: true` (→ `DO NOTHING`, needs only INSERT).
- **`Container(alignment: …)` hands its child LOOSE constraints**, so an
  unsized `CachedImage` floats inside its circle and leaves a rim.
  Meanwhile `CachedImage` hands its **errorBuilder TIGHT** constraints,
  so a bare `Text` paints top-left. Size the image; `Center` the
  fallback.
- **Curves ending in `…Back` overshoot past 1.0 by design.** Feeding one
  into `Opacity` asserts and crashes debug builds. Scale wants the
  overshoot; opacity never does — clamp it.
- **Flattening a navy surface means re-checking every foreground that
  assumed a dark backdrop** — status-bar icon brightness, white-on-
  frosted buttons, badge borders. None of these throw; they just go
  invisible.
- **Fixed height + text that can wrap** is the recurring overflow
  source: the chat scene's `height: 104`, the EGW list-mode cover, the
  library chip row's 44dp against a 12dp shadow. Let content size
  itself.

## Environment

- The working directory is the **PARENT** of the repo. Use
  `-C adventconnectzw` or absolute paths; the Bash tool resets cwd
  between calls.
- **`python` is NOT installed; `node` v24 is.** Use node to JSON-encode
  SQL for the Supabase Management API.
- **Full APK builds are blocked on this machine.** Only `flutter
  analyze`, `flutter test` and `flutter build bundle` can verify
  anything — which is why the render tests exist. **Add one for any
  screen you redesign.** `test/onboarding_film_test.dart` caught two
  already-shipping overflows nobody had noticed, plus a crash in
  brand-new code.
- The Supabase PAT is not stored anywhere. Ask for it if a migration is
  needed, and never write it to a file.
- To reproduce the exact request the app makes, a real user JWT can be
  minted: `POST /auth/v1/admin/generate_link` (service_role) → take
  `hashed_token` → `POST /auth/v1/verify` with **`token_hash`** (not
  `token`).

## Nothing is blocked on the founder

The claim-button discoverability question was answered by building it: a
card instead of a text link, and claimed churches keep an appeal route.
