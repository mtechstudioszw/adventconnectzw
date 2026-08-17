# Advent Connect ZW — open work

Last updated 17 Aug 2026. Ordered by priority. Everything here is either
diagnosed or has a stated unknown — nothing is a guess.

---

## 0. Blocked on the founder (nothing ships until these move)

- [ ] **Rotate the leaked Supabase token.** An `sbp_` PAT was pasted into
      chat on 16 Aug. The previous one was already rotated and now returns
      `Unauthorized`; this one is still live.
- [ ] **Move auth email off Gmail.** FOUNDER CHOSE "stay on Gmail for now"
      (17 Aug), so this stays open and WILL recur. Raising `rate_limit_otp`
      is **not** a workaround — Gmail throttles bursts itself and caps
      ~500/day, so a higher Supabase limit converts a clean error into a
      silent Gmail drop. The per-email throttles are already correct and
      are not the leak (reset 3/hr via `check_and_consume_rate_limit`,
      signup resend 3/hr via patch_125 plus exponential local backoff).
      The problem is that the **30/hr OTP budget is project-wide and
      shared between signup verification and password recovery**, so
      ordinary signup traffic exhausts it and resets then fail.
      `smtp_host` is `smtp.gmail.com`,
      `smtp_user` is `adventconnectzw@gmail.com`, with
      `rate_limit_email_sent: 150/hr` and `rate_limit_otp: 30/hr`.
      **This is why codes get spammed AND why reset codes then stop
      arriving — they are the same event an hour apart.** Gmail consumer
      SMTP throttles automated bursts and caps ~500/day. Needs a
      transactional provider (Resend / Postmark / SendGrid) + DNS. Founder
      decision: billing + domain.
  - [ ] Check whether Gmail has already suspended the account.
  - [ ] Establish whether the spam is inbound abuse or own testing — it
        changes whether the fix is rate-limiting or capacity.
- [ ] **Community Guidelines are consolidated to the live 8-section
      version** (done) — no action, noted so it is not re-litigated.

## 1. Pending action, needs a release

- [ ] **Turn on the quiz ready check** once a build containing its client
      half is live:
      `UPDATE public.app_config SET value='on' WHERE key='quiz_ready_check';`
      Until then live match behaves exactly as it does today (verified).
- [ ] **`app_events` stays at 0 until a build with the UUID fix ships.**
      Do not build the admin analytics dashboard before there is data.

## 1b. Fixed 17 Aug (needs a RELEASE to reach anyone)

- [x] **Dark mode: onboarding film + create sheet.** Three founder reports
      — "ready for sabbath not visible", "onboarding not premium", "create
      sheet is white" — were **one cause**: the film hardcoded 104
      `AppColors` refs and used `context.palette` zero times, under a
      scaffold that *did* flip. Migrated; `AmbientPainter` now takes a
      required `dark` (6 call sites). Verified by golden render in both
      brightnesses; light mode unchanged. Pinned by
      `test/onboarding_dark_mode_test.dart`.
      **The founder cannot see any of this without a new build.**
- [x] **Auth rate-limit copy was lying.** Every rate-limit error said
      "wait a minute and try again" when the project-wide OTP window is an
      **hour**, so people retried at 60s, failed, and retried — which is
      itself much of the "codes are getting spammed" report. Now states
      the real window and offers Google (needs no emailed code); the
      per-email cooldown quotes GoTrue's own number. Pinned by
      `test/auth_rate_limit_copy_test.dart`.
      **Note this does not fix the cause — see §0.**

## 2. Bugs — diagnosed, not fixed

- [ ] **Sabbath School opens the wrong day.** The day mapping is *correct* —
      verified against the live API (lesson 08 = 15–21 Aug, `DD/MM/YYYY`,
      index 2 = Monday). **Prime suspect: the
      `ss:days:$code:$quarterlyId:$lessonId` cache serving last week's
      lesson**, so nothing matches today and `_todayIndex()` falls back to
      index 0. Needs a device to confirm.
      - Quirk: the API returns **8** days and days 07/08 **share one date**.
        Any "one day per date" assumption breaks on it.
- [ ] **Church screen is cut off in full screen.**
- [ ] **Offline refresh gives no feedback.** Founder wants a 3-second
      "you're offline, try again later" popup on Home pull-to-refresh, and
      the same on other screens. **Check `OfflineBanner` in `main.dart`
      first — it already exists.**
- [ ] **The church card shows FOLLOWERS, not members** — measured against
      production 17 Aug, and this is the real answer to the founder's
      "verify the member count is actually Advent Connect members".
      - `churches.members_count` is 0 for all **2,600** rows — a dead
        column, and NOT the bug: `church_model.dart:74` already reads
        `follower_count` first and falls back to it, so nothing shows 0.
      - But the two measure different things. `profiles.church_id` is
        "this is my church" — **156 members across 116 churches**.
        `churches.follower_count` is "I follow this church" — **158
        followers across 117 churches**. You can follow a church you do
        not attend, and a member may never tap Follow.
      - The card reads `'${church.membersCount} on Advent'`
        (church_details_screen.dart:515), which is the follower count. The
        vague label hides it rather than making it true.
      - **Fix:** count from `profiles.church_id`. Prefer a read-only RPC
        over a trigger — `church_friend_counts()` (patch_176) is the
        precedent for returning bare numbers, and CLAUDE.md's loudest
        warning is about triggers touching `profiles`.

## 3. Features requested, not started

### EGW batch (founder, 17 Aug) — 2 fixed, the reader still BLOCKED

- [x] **Dark mode "doesn't work in EGW" — FIXED.** Not a missed
      `context.palette`: `egw_tab` and `pdf_viewer_screen` chrome were
      already palette-aware. The PAGE is a rendered PDF, so the only lever
      is the renderer's own `nightMode`, and that was a hardcoded
      `bool _night = false` with a manual app-bar toggle that never
      consulted the theme. Now an override (`bool? _nightOverride`) that
      follows app brightness until the reader explicitly flips it.
- [x] **"Continue reading" showed the wrong book — FIXED.** Two causes:
      (1) the reader persisted the page ONLY in `onPageChanged`, so a book
      opened and read without swiping never counted as started; (2) the
      hero filtered on `PdfProgress.hasStarted`, so that book was excluded
      and the previous one stayed. The reader now marks a book started on
      render (only when absent, so it cannot clobber a real resume page),
      and the hero keys on `EgwPrefs.lastOpenedAt` — which `_open` records
      unconditionally — falling back to progress for older books.
- [x] **Share cards are branded.** `VerseShareSheet` now carries
      `assets/icon/logo.png` beside "Advent Connect ZW", and the hardcoded
      "KJV" credit is a parameter, so the same card serves an EGW quote as
      **Ellen G. White**. Used by Bible + Today card today.
- [x] **Sabbath School image share — DONE 17 Aug.** The lesson's Share
      button now opens a sheet: "Share a link" (the old behaviour) plus the
      day's verses, each tapping through to the branded card with
      `attribution: 'Sabbath School'`.
      Design calls made rather than asked:
      - **A verse, not the day.** A whole day's reading cannot be a card;
        the day already ships its scripture in `SsDayContent.bible`, which
        is exactly the shape the card was built for.
      - **The list only appears when there is a choice** — one verse goes
        straight to the card, none falls back to the plain link.
      - **Attribution is "Sabbath School", not "KJV".** The lesson feed
        serves whichever translation the language edition uses, and naming
        the wrong translation on a shared image is worse than naming none.
      - `_DayPage` reports its fetched content up via a new `onLoaded`, so
        the share sheet reads verses already on screen instead of
        refetching.
      - `ssPlainText()` made public in `ss_html_text.dart` — the `bible`
        map is HTML, and a stray `&mdash;` or `<p>` on someone's WhatsApp
        status is not fixable after the fact. Pinned by
        `test/ss_share_verse_test.dart`.
- [ ] **EGW reflowable reader + quote cards** — the big one. Founder chose
      options 1+3. **NO LONGER BLOCKED (17 Aug).** The text source is
      settled: **EPUB**, from the same server as the PDFs
      (`media2.egwwritings.org/epub/en_<CODE>.epub`, HTTP 200 verified for
      all 61, ~0.6–1 MB each). Do NOT probe the egwwritings.org API and do
      NOT extract from the PDFs — both were the old plan, neither is
      needed. Full reasoning in the `egw-text-source-solved` memory.
      Why EPUB wins, verified by unzipping `en_SC.epub`:
      - clean EPUB 2 XHTML, one file per chapter, real `<p>` paragraphs;
      - **canonical page numbers inline** as
        `<span epub:type="pagebreak" title="18">`, so a quote card can
        cite "Steps to Christ, p. 18" accurately;
      - **scripture pre-tagged** as
        `<span class="bible-kjv" title="Colossians 2:3">`, so references
        can link into the app's own Bible tab;
      - `toc.ncx` + `content.opf` give chapters and spine order.
      `flutter_pdfview` exposes no text layer at all, so highlight / copy /
      share-a-quote is impossible on the PDF path — not merely harder.
      - [x] `egw-seed/fetch_all.sh` FIXED: it fetched EPUBs only when a
            cover was missing and then `rm -f`'d them — the EPUB was
            treated as a means to a cover, which is why only 11 of 61
            survived. Now always fetched and kept. **Not run yet** (~50
            downloads); needs a go-ahead.
      - [x] **All 61 EPUBs fetched** (17 Aug), zero failures, 42 MB.
      - [x] **Parser built** — `EgwEpubParser` → `EgwBook`. Verified against
            all 61: 46.3M chars, 21,676 page anchors, 17,652 scripture
            refs, no failures. 12 books have NO page anchors — they are the
            daily devotionals, organised by DATE, so cite those by date.
      - [x] **Reader built** — `EgwReaderScreen`. Day/Sepia/Night as real
            grounds (never pure black or white), type size that reflows,
            chapter contents with printed start pages, select-to-share a
            quote citing the canonical page, scripture rendered as a link.
      - [x] **Paginated with a page turn** (founder: "like an actual book").
            `EgwPaginator` measures and cuts chapters into screen-sized
            pages; the turn cancels PageView's slide and rotates the
            outgoing page about its left edge. Turn by swipe OR by tapping
            the outer third; the middle toggles the chrome.
      - [x] **Wired up (17 Aug).** `EgwTab._open` loads the EPUB and opens
            `EgwReaderScreen`; anything that fails — no EPUB, no signal on
            a first open, a file that will not parse — falls through to
            `PdfViewerScreen`. A member is never told a book on the shelf
            cannot be opened. `EgwBookService` caches to the app cache dir
            keyed by URL hash (same shape as the PDF path, so an opened
            book works offline), parses in a background isolate via
            `compute`, and writes to a `.part` file it renames on success
            so an interrupted download cannot leave a truncated EPUB.
      - [x] **DEPLOYED (17 Aug).** patch_206 adds `library_items.epub_url`
            and backfills it; all **61/61** EGW books now have one, and all
            **61 EPUBs are uploaded and byte-verified** in
            `library/egw_book/en_<CODE>.epub`. The first upload run was cut
            off after 49 files (12 × HTTP 000) — `finish_epubs.sh` in the
            session scratchpad re-checks Content-Length per file and
            uploads only what is missing, so it is safe to re-run.
            Two books needed hand-mapping: **The Great Controversy** and
            **Steps to Christ** were uploaded before the `en_<CODE>` naming
            and have timestamped PDF filenames, so the patch matches them
            on title instead.
      - [x] **Highlighting done (17 Aug).** Select → "Highlight" in the
            menu; selecting it again offers "Remove highlight". The wash
            re-renders on reopen.
            Stores the PASSAGE TEXT, not a character offset, and that is
            deliberate: the reader repaginates on every type-size, viewport
            or orientation change, so an offset is meaningless by the next
            session. Matching text survives all of it. Accepted cost is
            duplicates — a passage occurring twice in a chapter highlights
            both — which is rare and far better than a highlight drifting
            onto the wrong sentence.
            Stored WITHOUT the `pref:` prefix on purpose, so sign-out
            clears it: highlights are personal content and must not be
            inherited by the next member on a shared phone. (Reading
            settings ARE `pref:` — type size belongs to the handset.)
      - [ ] **Highlights are device-local.** They do not sync, so they are
            lost on sign-out and do not follow a member to a new phone. A
            `egw_highlights` table + RLS behind the same `EgwHighlights`
            API is the follow-up if the founder wants it.

      Traps hit, worth not re-learning:
      - The measurer and the renderer MUST use the same spans. Measuring
        plain text while rendering a `WidgetSpan` for each page number
        pushed an extra line and overflowed pages.
      - `gapAfter` must match `_block`'s padding exactly — a 10px drift on
        headings overflowed every page carrying one.
      - No `SingleChildScrollView` inside the page: a second scrollable
        under one `SelectionArea` makes drag-select assert. An overflow
        stripe is *wanted* there — it exposes a measurement bug instead of
        hiding it.
      - `SelectionArea` wins the gesture arena, so tap handling needs a raw
        `Listener`, and page text must be `Text`, not `SelectableText`. Means rendering *text* rather than PDF pages, which is
      what removes the page numbers and unlocks highlight / copy /
      share-a-quote and Day/Sepia/Night. `PdfViewerScreen` is the current
      path. **No EGW features have been added yet.**
- [ ] **Friend names on church cards** ("1 friend here → show who"). Was
      parked 16 Aug, **un-parked 17 Aug**. Needs a new RPC —
      `church_friend_counts()` deliberately returns a bare number
      (patch_176), and reversing that privacy posture is approved.
- [ ] **Church admin dashboard: events** should post as the church with its
      photo. *Posts* are fixed; events were reported in the same breath and
      are unverified.
- [ ] **Church admin dashboard — what else belongs there?** Open question
      from the founder.
- [ ] **Quiz live match reach.** Only **7 `quiz_profiles` rows exist for 200
      members**.
      **CORRECTION (17 Aug): this is NOT a name gate.** I said earlier that
      live match forces you to invent a quiz name first and that this was
      throttling the funnel. That was wrong, and checking the server settled
      it:
      - `quiz_profile_ensure()` **already auto-creates** the profile from the
        member's first name, with unique-collision handling ("Tendai",
        "Tendai 1", …), and `quiz_match_find` calls it before anything else.
      - **No database function raises `QUIZ_PROFILE_REQUIRED` at all**, so
        `QuizMatchService`'s `QuizProfileRequired` branch — and the profile
        sheet it opens — is **dead code** on that path.
      So there is no gate to remove. 7 profiles exist because only ~11 people
      have ever opened live match; the row is created on first search. The
      real problem is **discovery and having somebody to play**, so the work
      is promoting the entry point and solving the empty-lobby problem
      (scheduled match times, or leaning on the async challenge that already
      works) — not removing a barrier that isn't there.
      - [ ] Separately: delete the dead `QuizProfileRequired` path.
            **Verified against production 17 Aug: ZERO functions contain
            `QUIZ_PROFILE_REQUIRED`** (`select count(*) from pg_proc where
            prosrc like '%QUIZ_PROFILE_REQUIRED%'` → 0), so the branch can
            never run. Since `quiz_profile_ensure()` auto-creates the
            profile there is no gate to raise, so DELETE rather than
            implement.
            Scope carefully: the exception class + its throw site in
            `quiz_match_service.dart:200` and the three
            `on QuizProfileRequired` catches in
            `quiz_matchmaking_screen.dart` (142, 190, 292). **`QuizProfileSheet`
            itself is NOT dead** — the leaderboard (line 68) and a rename
            flow (matchmaking:309) both use it legitimately. Deleting the
            sheet would break both.
- [x] **Quiz lobby restyle — DONE 17 Aug.** Built exactly to the chosen
      direction: Daily Challenge hero (streak promoted from a corner digit
      to a labelled "N day streak" chip) → full-width live-match strip
      showing "N online now · play someone" → quiet MORE WAYS TO PLAY list
      (Quick Play, Survival, Speed Round, Fix Your Mistakes, Challenge a
      friend, Leaderboard). The 2-up `GridView` is gone; `_ModeTile`,
      `_ChallengeTile` and `_LiveMatchTile` are replaced by `_ModeRow` and
      `_LiveMatchStrip`. Rows restore each mode's blurb, which the grid had
      dropped for space. `flutter analyze` clean, 373 tests pass.
      **CAVEAT: not visually verified.** The lobby cannot be golden-rendered
      on this machine — it pulls in audioplayers, whose per-sound
      EventChannels throw `MissingPluginException` asynchronously and defeat
      both mock handlers and exception draining. Overflow risk is handled
      structurally (every Row text is `Expanded`/`Flexible`), but the
      hierarchy itself needs a device or the founder's eye.
      Original brief, kept for reference:
      Today's challenge dominates the screen, carrying the streak and whether
      it has been played. The other five modes drop to a quiet list beneath
      it. This is the same decision that fixed the create screen: the fault
      is a uniform grid of glass tiles at one visual weight, so nothing reads
      as the thing to do. Keep the dark arena canvas — only the hierarchy
      changes.
      Order on the screen: Daily Challenge hero → live-match strip (which now
      shows "N online now") → MORE WAYS TO PLAY list (Quick Play, Survival,
      Speed Round, Fix Your Mistakes, Leaderboard).

- [ ] **Quiz entry from Home — DIRECTION CHOSEN (17 Aug): BOTH.**
      Two entry points doing two different jobs:
      - **A Daily Challenge card in the Today slot** — the question teaser,
        "5 questions · 2 min", and the streak, tapping **straight into the
        questions and skipping the lobby**. Streaks are what make a daily
        quiz sticky and nothing on Home currently says one is waiting.
      - **A live dot on the existing Quiz pill** in the Library row — lit
        when somebody has challenged you, or showing "N on". This is the
        "someone wants you" signal; the card is the habit.
      - [x] **The plumbing + the live dot are DONE (17 Aug).** New
            `QuizHomeSignal` (`lib/services/quiz_home_signal.dart`) caches
            the invite count, because `QuizMatchService.invites()` is a
            **one-shot RPC** and Home must never call it per build. It
            shares one in-flight request between callers, has a 20s floor
            (`force: true` for deliberate refreshes), re-exports
            `PresenceService.onChange` for the online count, and is
            registered in `SessionReset` — statics outlive sign-out, so
            without that the next account inherits the previous player's
            dot. Refreshed from `HomeScreen._bootstrap`, and the quiz
            lobby writes back to it on `_refreshChallenges` so the dot
            goes out when the member deals with the invite (returning from
            the arena does NOT re-run Home's bootstrap). Dot verified by
            render in both brightnesses; pinned by
            `test/quiz_home_signal_test.dart`.
      - [ ] **The Daily Challenge card in the Today slot — NEXT.** Not
            started, deliberately: it is bigger than it looks. Scouted so
            the next session doesn't re-derive it:
            - `TodayCard` is a `PageView` of `_Slide`s assembled in
              `_slides()` (today_card.dart:145). Adding one is easy — the
              slide list is already conditional per content.
            - The hard half is "taps straight into the questions,
              **skipping the lobby**". Do NOT duplicate the lobby's
              `_play`/`_runRound`: that flow owns round → results →
              streak, challenge submit/send, and the pending-opponent
              claim, and a second copy will drift.
            - Instead thread an intent through the route. `/quiz` is
              `QuizBootScreen` (a warming GATE that crossfades into the
              lobby in place — router_config.dart:673), so pass
              `extra` → boot → lobby and have the lobby auto-run
              `_play(QuizMode.daily)` once on mount. Reuses the whole
              tested flow.
            - The streak and played-today state come from
              `QuizProgressService.currentStreak()` /
              `.playedToday()`, both synchronous.
      - [ ] **Home live-match surface** — still open. `QuizHomeSignal`
            now supplies everything it needs (invites + online), so this
            is presentation only.

- [ ] **Live match must be DISCOVERABLE, not buried** (founder, 17 Aug).
      Today it is two taps deep and behind a tile: Home → Quiz → Live match.
      Nobody finds it, which is most of why only ~11 members have ever
      played one.
      Surface it on **Home**, not only inside the quiz lobby. It is the only
      real-time, person-to-person thing in the whole app, so it earns a slot
      the way Stories does — and it is strongest exactly when it is true:
      - when somebody has **challenged you** → that is a notification-grade
        event and should be unmissable on Home, not a number on a tile;
      - when **others are online** → "7 online now · play someone" is a
        reason to tap that a static label can never be;
      - when **nobody is around** → say so and offer the async challenge,
        rather than advertising an empty arena (already fixed inside the
        lobby tile; the Home surface must do the same).
      The presence roster already gives the count — `PresenceService
      .onlineUsers` — and `QuizMatchService.invites()` already gives pending
      challenges. The missing piece is only the Home surface itself.
- [ ] **Suggested news** — done (Keep reading rail), listed so it is not
      rebuilt.

## 3a. ADS — THE WHOLE NEXT SESSION. Appodeal migration + quiz monetisation

**Provider chosen: Appodeal** (founder, 17 Aug). AdMob is out — the account
AND the app were disapproved, so fill is zero today regardless of code.

### Credentials + facts
* App key: `1f6b42e57ed20ce3e9378dc3a59a46578c982215c968cca1`
  (NOT a secret — it ships inside every APK by design. Unlike the Supabase
  PAT, this one does not need rotating.)
* Bundle: `io.supabase.adventconnectzw.advent_connect_zw`
* Package: **`stack_appodeal_flutter: 4.2.0`** (official, Android+iOS,
  published ~late June 2026). Pin EXACT per project policy.
* Floors already clear: app `minSdk` is 24 (needs 23), iOS target 13.0
  (needs 13.0). No bump required.

### The two things that will surprise you
1. **Appodeal has NO ad unit IDs.** You init with the App Key and request by
   TYPE (interstitial / banner / MREC / rewarded / native); Appodeal runs the
   waterfall. The dashboard's "Ad Units" page configures each type across all
   networks — it is not where IDs are minted. Nothing to paste into code.
2. **Appodeal has NO App-Open format.** The available list is Interstitials,
   Banners, MREC, Videos, Rewarded Videos, Native. So `AppOpenAdManager` has
   no equivalent and must become an interstitial-on-resume or be dropped —
   and if it becomes an interstitial, `_appOpenBlockedPrefixes` in
   `main.dart` (chat, prayer, auth, marketplace, events, churches, library,
   news) must carry over to it.

### Network reality (from the founder's dashboard, 17 Aug)
Most networks are blocked: `does not pass all restrictions` (AppLovin,
BigoAds, DT Exchange, ironSource, Mintegral, VK), `has to be connected
manually` (AdMob, Amazon, Meta, Yandex), `not connected yet` (Inmobi).
**Available to start: BidMachine, Backfill, Ad Server Campaigns.** More
unlock with live store traffic. Do NOT connect AdMob — it is disapproved.

### Invariants that MUST survive the swap
* `main.dart:134-157` — `await PremiumService.init()`, then
  `if (!PremiumService.isActive) startAds()`, plus the listener that calls
  `AdsService.discardCachedAds()` on a mid-session purchase and `startAds()`
  on lapse. **A subscriber must never initialise an ad SDK at all** — this
  ordering is provider-agnostic, so keep the new init inside
  `AdsService.init()`.
* Ad surfaces gate on `AdsService.canRequestAds`.
* `discardCachedAds()` needs a real Appodeal implementation.
* The banner trap: a 50dp banner became a full-screen bar THREE times from a
  `Center` without `heightFactor: 1`.
* `docs/app-ads.txt` — Appodeal supplies its own lines (many, one per
  mediated network). ADD them; `docs/` is a live site and must never be
  deleted.
* Appodeal ships its own GDPR/CCPA consent dialog, which replaces the
  current EU consent flow — do not run both.

### Quiz monetisation (founder: "we are sitting on top of money")
Correction to the premise: **the quiz already serves rewarded ads** —
`quiz_round_screen.dart:549`, for lifelines. But the funnel is tiny: it
fires only when the player is out of coins AND an ad happens to be loaded,
and grants the lifeline free when none is ready.

The founder proposed lives-that-reset + an ad to earn one. **Advised
against gating scripture** — this is a church app and making Bible study
harder to force ad views risks trust. Founder agreed to revisit as part of
this work. The principle recommended instead: **make the reward additive,
not the block punitive** — which also converts better.

Ranked placements to build:
1. **Survival continue.** Survival is already sudden death; offer "watch to
   continue your run" at the moment of death. Highest-converting placement
   in mobile gaming and purely additive.
2. **Double your points** at round end.
3. **Explicit coin top-up** in the lobby — a real button, not a silent
   fallback. Probably multiplies current impressions on its own.
4. **Streak repair** — one ad restores a missed day. Cap at once a week so
   the streak still means something.
5. **Lifelines** — keep, but make the ad offer visible rather than hidden.

**Do NOT gate the Daily Challenge.** It is the habit that brings people
back; blocking a streak behind an ad is the placement most likely to feel
extractive.

**Premium gets these free** (continues, lifelines). That makes the
subscription more valuable and costs nothing, since subscribers never load
an SDK.

## 3b. Old AdMob notes — kept for the app-ads.txt / blocklist detail

- [ ] **The founder intends to move off AdMob mediation** (17 Aug). Nothing
      picked yet. Read before touching it:
      - **The AdMob account is disapproved and under appeal** — that is
        account-level, not app-level, and nothing in the codebase caused it
        or can fix it.
      - **`docs/app-ads.txt` holds the AdMob publisher authorisation**
        (`google.com, pub-2916679989954369, DIRECT, …`). Google crawls it.
        A new provider means a NEW line, usually alongside the existing one
        rather than replacing it — and `docs/` must never be deleted, it is
        a live site.
      - `AdsService` + `AppOpenAdManager` own SDK init, EU consent and the
        App-Open cap. `main.dart` deliberately resolves **premium before
        ads** so a subscriber never starts the ad SDK at all — preserve that
        ordering with any new provider.
      - Ad surfaces gate on `AdsService.canRequestAds`, and there is a
        standing trap: a 50dp banner became a full-screen bar three times
        because of a `Center` without `heightFactor: 1`.
      - `_appOpenBlockedPrefixes` in `main.dart` lists the routes where a
        full-screen ad must never appear (chat, prayer, auth, marketplace,
        events, churches, library, news). Any new provider's interstitial
        needs the same blocklist.

## 4. Known-unfinished, lower priority

- [ ] **App cold-start, the native half.** The splash's own budget is fixed
      (capped to the gold-ring duration, ~2.5s worst case, pinned by a
      test). Native launch + engine init is unmeasured and **needs a device**
      — `adb devices` is empty on this machine.
- [ ] **Watch:** `fetchContinueSeries` is now one RPC, but **all 1,494
      playlists have `is_category = true`**, so that flag distinguishes
      nothing. Its only reader, `YoutubeService.fetchPlaylists()`, is **dead
      code** — check before "fixing" the flag.
- [ ] **More dark-mode faults will surface.** Appearance now defaults to
      system, so un-migrated screens are reachable by default. The fix each
      time is migrating that widget to `context.palette`, **not** reverting
      the default.

## Explicitly parked — do not start

- End-to-end encryption.
- **5-player live match.** The founder chose the ready check alone.
  `quiz_matches` is structurally two-player (`player_a`/`player_b`); this
  would need a participants table, a new state machine and new arena UI.

---

### Standing rules that keep earning their place

1. **Check whether it already exists before building it.** Ten "missing"
   features this month turned out to be built and quietly broken — the most
   recent being the quiz "name gate" above, which does not exist. The rule
   catches wrong diagnoses, not just wasted builds: acting on that one would
   have meant removing a barrier that was already gone while the real cause
   (an empty lobby) went untouched.
2. **Query with an authenticated context**, not the anon key — several
   tables are `TO {authenticated}` and read as empty otherwise.
3. **Verify against the DB, a test, or a render — never by reading code.**
   Renders are possible with no device: a throwaway `matchesGoldenFile`
   test plus `--update-goldens` writes a PNG you can look at.
4. **A route name is just a string until someone taps it.** Two dead routes
   found this month. `appRouter.configuration.namedLocation('x')` in a unit
   test catches them.
5. **Only the UI isolate may refresh auth tokens.** A second GoTrue client
   revokes the app's own refresh token and signs the user out.
