# NEXT SESSION — Advent Connect ZW

Paste this whole file as the first message of the next session.

---

## Where things stand (2 Aug 2026)

All work is pushed. `main` head: **"Announcement reactions: schema, RPCs
and admin notifications"**. `flutter analyze` is clean apart from **4
pre-existing infos** in files nobody touched; **67/67 tests pass**
(was 38). `flutter build bundle` succeeds.

Migrations **178–182 and `20260802120000_announcement_reactions.sql` are
applied to production and verified — do NOT re-apply them.**

The 2 Aug session finished the first-run path, redesigned Search, the
composer and the church profile, and shipped the announcement-reactions
**backend**. What follows is a founder bug round plus two unfinished
items.

## Read first, before any code

1. `CLAUDE.md` — the colour table's "Dark Navy for headers" line is
   retired. **Headers are FLAT on `palette.scaffoldBg`, never navy.**
   Account screens use `AuthShell`.
2. Memory files `bug-round-jul29`, `open-backlog-jul29`,
   `motion-must-not-cost-time`.
3. `git -C adventconnectzw log --oneline -12`

---

# PART 1 — Founder bug round (2 Aug)

Dictated in one burst. Several already have a confirmed root cause —
those are marked **[CONFIRMED]** and you can go straight to the fix.

### 1. QR code — logo placement
`lib/widgets/friend_qr_sheet.dart`. The logo is currently laid over the
QR. **Cut a round hole in the middle of the QR and seat the logo in it**,
the way WhatsApp/Instagram do. Put a solid round plate behind the logo so
the quiet zone is real, and keep error correction high
(`QrErrorCorrectLevel.H`) so the occluded modules stay recoverable —
otherwise the code stops scanning on some readers. **Verify it still
scans after the change.**

### 2. Settings — unreadable text **[CONFIRMED: mojibake]**
`lib/screens/settings/settings_screen.dart:1010` reads
`'Made with care â€¢ MyTech Studios Zw'`. That `â€¢` is a `•` written as
UTF-8 then decoded as Latin-1 — this is the "next word I can't even read".

**It is not the only one.** A sweep found it in three files:
- `lib/screens/settings/settings_screen.dart` — 14 occurrences
- `lib/screens/marketplace/product_details_screen.dart` — 6
- `lib/screens/churches/churches_screen.dart` — 5

Fix all 25, not just line 1010. Grep for `â€`. Consider a CI grep so it
can't come back.

### 3. Settings — "Watch new videos & live"
Founder flagged this item. Ambiguous whether it's the same mojibake, a
broken toggle, or a dead route — **check the item itself before
assuming**; it sits near the corrupted strings above.

### 4. Profile photo — white edges **[known trap]**
Round frame must clip like WhatsApp with no white rim. This is the
documented loose-vs-tight bug: `Container(alignment:)` gives its child
**LOOSE** constraints, so an unsized `CachedImage` floats inside its
circle and leaves a rim. **Size the image explicitly and `Center` the
fallback.** The same fix already landed on the church avatar in
`church_details_screen.dart` — copy that shape. Check every avatar, not
just the profile screen.

### 5. Home "Events" chip goes to the wrong place **[CONFIRMED]**
`lib/screens/home/home_screen.dart:1252` —
`onEvent: () => _handleCreate(CreateKind.event)` opens the **create an
event** composer, while both neighbouring chips navigate
(`onChurches: pushNamed('churches')`, `onDonate: pushNamed('donate')`).
Should be `context.pushNamed('events')`. Confirm the route name in
`router_config.dart` first.

### 6. Quiz game has no sound
No audio at all. Determine whether sounds are missing assets, never
wired, or playing into a silenced/incorrect audio session. **Mind the
rules in memory `audio-background-playback-fix` — do not swap the
platform audio setup to fix this.**

### 7. Watch notifications have no thumbnail
"A channel posted a video" / live notifications should show the video's
thumbnail, like YouTube. Needs a big-picture notification (Android
`BigPictureStyle`) carrying the YouTube thumbnail URL. Start at
`lib/services/push_service.dart` and whatever writes watch notifications.

### 8. Bible verse share should generate an image
The Library's **verse of the day** share already renders a picture with
the verse on it. Reuse that generator for **any** Bible verse share so
sharing from the Bible reader produces the same image. Lift the existing
generator into a shared widget/service rather than duplicating it.

### 9. Devotion cards on Home don't deep-link
Tapping a devotion card should open **that exact thing** — the Sabbath
School lesson shown, the hymn of the day, the music of the day. Each card
needs to carry its target's id and route to it.

### 10. Chat must work offline (WhatsApp-style)
Two parts:
- **Reading:** messages readable offline and painted instantly from cache
  (Hive), then reconciled — not re-fetched with a spinner every time.
- **Sending:** a message composed offline queues with a clear pending
  state ("will send when you're back online") and flushes on reconnect.

Memory `feed-ranking-findings` says chat **already queues offline** in
some form — **verify what exists before building it again.** Mind the
**bigint id trap** from `chat-redesign-task`.

### 11. Prayer screen highlights the wrong nav tab
Entering Prayer lights up the **Profile** tab. The nav's selected-index
derivation is wrong for this route.

### 12. Church and Prayer screens show tabs that aren't real
Both render something that reads as a tab bar but isn't. Either make them
genuine tabs or stop them looking like tabs — the complaint is the false
affordance. Likely the same root cause as #11.

### 13. YouTube channels show the wrong avatar
Channel rows should display the channel's **actual YouTube profile
photo**. Check whether `YoutubeService` fetches channel
`snippet.thumbnails` and whether quota-aware caching drops it. Memory
`brief03-open-bugs` documents a **self-healing quota hole with three cron
jobs** — read it before touching YouTube fetching.

---

# PART 2 — Unfinished from the last session

### A. Announcement reactions — UI only (backend is DONE)
The migration is **applied and verified on production**; the Dart service
layer exists in `lib/services/church_service.dart`. **Nothing is wired
into a screen.** Build:
- a reaction bar on announcements (`AnnouncementReaction` enum — amen /
  praise / pray / love, emoji + label already defined);
- the admin dashboard panel from
  `ChurchService.fetchAnnouncementReactionStats()`.

Available and tested end-to-end against production:
- `set_announcement_reaction(bigint, text)` → `{mine, counts}`. Passing
  null, or the reaction you already have, **clears** it — so tapping the
  same face twice un-reacts.
- `announcement_reactions_for(bigint[])` → batched read for lists.
- `church_announcement_reactions(bigint, int)` → admin-gated analytics.

Admin notifications **collapse**: one live notification per announcement
per admin, body rewritten with the running count while unread. Verified:
two reactions produced exactly one notification, and an admin is never
notified of their own reaction.

### B. Chat settings redesign — **STILL BLOCKED**
`lib/screens/messaging/chat_privacy_screen.dart`, reached from the ⋮
sheet in `chat_screen.dart`. The founder asked for a redesign **"+ new
features"** and has never said which. **Ask before building** — bring a
shortlist rather than guessing. #10 above (offline chat) is adjacent and
may absorb part of it.

---

# Traps already paid for — don't rediscover them

- **`CrossAxisAlignment.stretch` on a `Row` inside any scrollable is
  always a bug.** It hands the Row's unbounded cross-axis extent to
  children as a TIGHT constraint → "BoxConstraints forces an infinite
  height" → in release the widget paints **nothing** (blank grey, no red
  error box).
- **A supabase-dart `.upsert()` is `INSERT … ON CONFLICT DO UPDATE …
  RETURNING`**, so the table needs **SELECT *and* UPDATE** policies, not
  just INSERT. Missing either → 42501, usually swallowed by a `catch`.
  Bit three times. For a pure membership tuple pass
  `ignoreDuplicates: true` (→ `DO NOTHING`, INSERT only). Announcement
  reactions deliberately go through an RPC to sidestep this entirely.
- **`Container(alignment:)` gives its child LOOSE constraints** (an
  unsized `CachedImage` floats inside its circle, leaving a rim), while
  `CachedImage` gives its **errorBuilder TIGHT** constraints (a bare
  `Text` paints top-left). Size the image; `Center` the fallback. **This
  is bug #4 above.**
- **Curves ending in `…Back` overshoot past 1.0 by design.** Into
  `Opacity` that asserts and crashes debug builds. Scale wants the
  overshoot; opacity never does — clamp it. (`FadeTransition` is safe —
  it clamps internally — so it is NOT an instance of this.)
- **Fixed height + wrappable text** is the recurring overflow source, now
  seen four times. It can fail **silently**: the Search filter rail
  clipped its labels with no exception at all, because no Flex was
  involved to throw. Let content size itself.
- **Flattening a navy surface means re-checking every foreground that
  assumed a dark backdrop** — status-bar icon brightness,
  white-on-frosted buttons, badge borders. None throw; they go invisible.
- **`notifications` has no client INSERT policy, by design.** Anything
  writing one must be SECURITY DEFINER. See
  `notify_admins_of_announcement_reaction()` and
  `nudge_profile_incomplete()`.

# Testing rules learned this round

- Screens whose `initState` touches Supabase/Hive/the router need a
  constructor seam to be testable. Four exist and are the convention:
  `SplashScreen.autoNavigate`, `BiometricLockScreen.autoPrompt`,
  `SearchScreen.autoLoad`, `ChurchDetailsScreen.autoLoad`.
- **Test at 1.0x / 1.6x / 2.5x system text on a 360dp phone.** That sweep
  caught a 49px overflow on the lock screen, 95px in `AuthShell` (which
  was clipping all five account screens), and 97px on the church profile.
- **Reproduce before fixing, and let the test correct you.** Two
  hypotheses were wrong this round: the composer rows do NOT overflow,
  and `easeOutBack` into `FadeTransition` does NOT assert.
- When testing RLS-protected rows via the Management API, remember
  `notifications` SELECT is `auth.uid() = user_id` — query as the
  recipient or reset the role, or you'll conclude a write failed when it
  succeeded.

# Environment

- Working dir is the **PARENT** of the repo — use `-C adventconnectzw` or
  absolute paths; the Bash tool resets cwd between calls.
- **`python` is NOT installed; `node` v24 is.** Use node to JSON-encode
  SQL for the Supabase Management API. **`/tmp` does not exist** — write
  scratch files to the session scratchpad directory.
- The Management API `/database/query` endpoint returns only the
  **first** result set. Put mutations in a `DO $$ … $$` block so your
  final `SELECT` is the only one returning rows.
- **Full APK builds are blocked on this machine.** Only `flutter
  analyze`, `flutter test`, `flutter build bundle` verify anything.
  **Add a render test for any screen you touch.**
- Debug APKs build via GitHub Actions on every push to main → Releases.
- **The Supabase PAT is not stored anywhere. Ask for it if a migration is
  needed, and never write it to a file.** The PAT shared on 2 Aug went
  through chat and should be treated as compromised — ask for a fresh one.
- To reproduce the exact request the app makes, mint a real user JWT:
  `POST /auth/v1/admin/generate_link` (service_role) → take
  `hashed_token` → `POST /auth/v1/verify` with **`token_hash`** (not
  `token`).

---

Start with the confirmed ones (#2 mojibake, #5 Events chip) to land quick
wins, then #4 and #11/#12 which are likely one root cause each. Ask about
chat settings (Part 2B) early so it isn't blocked at the end.
