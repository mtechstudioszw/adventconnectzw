# Advent Connect ZW — open work

Last updated 18 Aug 2026. Ordered by priority. Everything here is either
diagnosed or has a stated unknown — nothing is a guess.

---

## 0. Blocked on the founder (nothing ships until these move)

- [ ] **Rotate the leaked Supabase token.** An `sbp_` PAT was pasted into
      chat on 16 Aug, and another was used for the 17 Aug DB work. Founder
      confirmed on **18 Aug that it has NOT been rotated** — both are still
      live and both are burned. No DB or Management-API work was done in
      the 18 Aug ads session for this reason; none was needed.
- [ ] **Appodeal "Publish App" is at 67% — three gates, NONE of them code.**
      Dashboard, 19 Aug: Privacy Policy, app-ads.txt, CMP.
      - **CMP** — *"CMP not integrated yet. No valid consent string detected
        in SDK requests from GDPR/CCPA zones."* This almost certainly means
        **"no traffic yet"**, not a bug: no build containing the Appodeal
        SDK has ever run, so the SDK has made zero requests and there is no
        consent string for Appodeal to have seen. The code side is
        deliberate — Stack Consent Manager ships INSIDE SDK 3.0+ and
        gathers consent during `initialize()`, which is exactly why our own
        UMP flow was DELETED (running both double-prompts the same user).
        **Do not "fix" this by adding a second consent flow.** It can only
        be confirmed by shipping a build and watching the dashboard.
        - **Raise with Appodeal support BEFORE shipping:** their Google-CMP
          guide expects a UMP privacy message, and UMP messages are
          configured in the **AdMob** console — which is disapproved. If
          Stack Consent Manager needs an AdMob-side message we may be
          blocked on the appeal. Ask; do not assume either way.
      - **Privacy Policy** — already published at
        `mtechstudioszw.github.io/adventconnect-legal/privacy.html` (the URL
        the Play listing points at). Likely just needs entering in the
        Appodeal dashboard.
      - **app-ads.txt** — the entry below. A publishing problem, not a
        content problem.
- [ ] **`app-ads.txt` IS NOT PUBLISHED. Revenue is still blocked.**
      The file is right and complete in the repo — 2,505 records in both
      `docs/app-ads.txt` and `legal-site/app-ads.txt`. **It is not what is
      being served.** Checked live on 19 Aug:

      | URL | What is actually there |
      |---|---|
      | `mtechstudioszw.github.io/app-ads.txt` | **ONE line**, the old AdMob entry `google.com, pub-2916679989954369, DIRECT, …` |
      | `mtechstudioszw.github.io/adventconnect-legal/app-ads.txt` | **404** |
      | `mtechstudioszw.github.io/adventconnectzw/app-ads.txt` | **404** |

      Two separate problems, and the second is the one that wastes time:

      1. The served file is **stale** — a single AdMob line, from before the
         Appodeal migration. AdMob is gone from the app and the account is
         disapproved, so that line authorises a seller we no longer use and
         authorises none of the ones we do.
      2. **Crawlers only read the DOMAIN ROOT.** The spec takes the
         developer website from the store listing, reduces it to a domain,
         and fetches `https://<domain>/app-ads.txt`. The Play listing points
         at `mtechstudioszw.github.io/adventconnect-legal/privacy.html`, so
         the domain is `mtechstudioszw.github.io` and the ONLY file that
         counts is the one at its root. Publishing to
         `/adventconnect-legal/app-ads.txt` would still be invisible.
         `github.io` is on the Public Suffix List, so
         `mtechstudioszw.github.io` is its own domain — that part is fine.

      **Fix:** replace the one-line file at the root of the
      `mtechstudioszw.github.io` Pages repo with `docs/app-ads.txt` from
      here. Then re-fetch `https://mtechstudioszw.github.io/app-ads.txt` and
      confirm it is 2,505 lines, not one. Founder action — that repo is not
      in this tree.
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

## 2b. EGW reader + Sabbath School batch (founder, 18 Aug 2026)

Eight items in one message, plus five more he reported live on 19 Aug.
**Ten are now fixed; two need his answer; two are open.** None of it is
verified on hardware — he has no device this session, so everything below
was reproduced and pinned with tests instead. See §3a.

### The one cause behind five of these reports

*"text size, day, sepia dosent work"*, *"save to shelf dosent work"* and
*"read offline download dosent work"* were **one bug in three places**: a
Hive write was `await`ed BEFORE the notifier that repaints was bumped, so
the page, the bookmark and the download tick could not change until the
handset finished writing. `CacheService.initialize()` starts a prune +
`compact()` of a box that grows on every feed refresh, so that await is
not free on a real phone. From the outside it is a dead button.

Everywhere it mattered the value now moves first and the disk catches up.
`writePref` reaches Hive's in-memory keystore before its first `await`, so
a read on the same frame already sees the new value — only the flush is
outstanding, and nothing on screen depends on it. **This is now a rule:
never `await` storage before the notifier that repaints.**

- [x] **The CI build was broken and had been since the Appodeal
      migration.** `:app:processDebugMainManifest` — Appodeal's core SDK
      declares `android:allowBackup="true"`, ours declares `false`, and the
      merger refuses to pick. `tools:replace="android:allowBackup"` settles
      it. **The value stays false**: auto-backup would copy auth state and
      cached personal content off the device, against the Play data-safety
      declaration. Fixed in `5115a48`.
- [x] **Text size / Day / Sepia.** Two independent bugs at once, both of
      the ones predicted below. The setters awaited the write (above), AND
      `showModalBottomSheet`'s `backgroundColor` was evaluated once at call
      time, so the sheet stayed white while a scrim dimmed the rest —
      almost nothing was left on screen to show the tap had landed. The
      sheet now paints its own ground and rebuilds off the same notifier as
      the page. Pinned by `test/egw_reader_settings_test.dart`, which fails
      against the old setters on exactly the founder's symptom.
- [x] **Save to shelf.** Same await; the sheet also stayed open until the
      flush returned. Pops on the same frame now.
- [x] **Read offline / download.** `EgwDownloadService.download` had **no
      timeout of any kind** — the identical bug fixed in `EgwBookService`
      on 18 Aug, in the twin this service was deliberately written to
      mirror. Only one half got the fix. Now 15s connect / 20s headers /
      10min transfer, closes its client, and verifies `Content-Length`
      before indexing (a truncated PDF is a valid PDF prefix, so nothing
      downstream could tell).
- [x] **Tap-to-turn removed** — founder: *"remove touching screen then
      goes to next page"*. It fired on the gesture people make while
      reading, and it is the same gesture as tap-to-highlight. Swiping
      still turns.
- [x] **The page-turn animation.** Was ~99° of rotation with heavy
      perspective, so the outgoing page went near edge-on and its text
      sheared into an unreadable wedge on every turn. Now ~29° with
      lighter shading; the hinge and the shading are what sell it as
      paper, not the depth of the angle.
- [x] **The book cover while a book opens.** The wait now shows the book —
      cover, title, "Opening…" — instead of a bare spinner over a dimmed
      shelf.
- [x] **Tap a sentence to highlight it.** Unblocked by removing
      tap-to-turn. The boundary rule is the part most likely to be quietly
      wrong — this shelf is dense with initials (E. G. White),
      abbreviations (vol., Mrs.) and verse references (Col. 2:3), and a
      naive split on `.` highlights two words and looks broken. A
      terminator only ends a statement when what follows looks like a new
      one, with an explicit exception for single-letter initials.
      `EgwHighlights.rangesIn` also gained a whitespace-tolerant fallback:
      passages are stored with whitespace collapsed while the source keeps
      its line breaks, so a plain `indexOf` could miss a passage that was
      genuinely there — it stored fine and simply never painted.
      Pinned by `test/egw_tap_highlight_test.dart`.

- [x] **Pull-to-refresh was broken across the WHOLE Library, not just EGW.**
      Founder: *"the refesh of egw dosent work"*, then *"if u swipe down it
      dosent refresh"*. One character:

          setState(() => _future = future)   // arrow body RETURNS the Future

      `setState` asserts that its callback did not return a Future — that is
      how `setState(() async {…})` is caught. The assert fires after the
      assignment but before `markNeedsBuild()`, and the throw escapes
      `_refresh`, so its `await future` never runs. `BrandedRefreshIndicator`
      awaits `onRefresh` to know how long to spin, so it got an exception
      and settled instantly however long the fetch took.
      **CI ships a DEBUG apk, so this fired on his phone on every pull.**
      Found in **eight** places: the EGW, Sabbath School and Music tabs, and
      five admin reload buttons. All now use a braced body.
      Pinned by `test/egw_tab_refresh_test.dart`, and
      `test/branded_refresh_indicator_test.dart` pins the indicator itself
      against every scroll-view shape the Library uses (including a shelf too
      short to scroll and an empty one) so the next report of this kind can
      be localised in one run.
- [x] **Sabbath School `'_dependents.isEmpty': is not true` — FIXED.** The
      founder's own repro solved it: *"when reading n u click the pencil icon
      n click back the screens turns red"*. `_openNote` created a
      `TextEditingController`, `await`ed `showModalBottomSheet`, then
      disposed it. **That await completes when the route is POPPED, not when
      it has finished leaving** — the sheet is mounted for the whole exit
      transition, so the controller died while a live `EditableText` was
      still listening, and the field failed on its way out while still
      registered as a dependent of the inherited widgets it had read.
      `InheritedElement.debugDeactivated()` then asserted. `autofocus: true`
      is why it happened every time rather than occasionally.
      The editor is now a `StatefulWidget` (`_DayNoteSheet`) that owns its
      controller, so the framework disposes it when the element actually
      unmounts. **The same shape was found in two more places** and fixed
      with it: `prayer_circles_sheet.dart` (new circle) and
      `church_admin_approvals_screen.dart` (reject reason), both with
      `autofocus` fields and eager disposal.
      Pinned by `test/ss_note_sheet_crash_test.dart` — **verified red
      against the original code**, failing with the founder's exact error.

### Needs the founder

- [ ] **"there no shelf"** — ambiguous, and the only report from 19 Aug not
      yet resolved. Save-to-shelf is buried behind a **long-press** on a
      cover, and the Saved shelf is a filter chip under the search box. Do
      not guess which half he means.

### Still open

### FIXED 18 Aug — "takes long to open a book, it loads for ever"

`EgwBookService._bytes()` had **no timeout of any kind**: not on the
connection, not on the transfer. A stalled socket on mobile data hung the
open screen indefinitely, because an `HttpClient` with no
`connectionTimeout` waits on the OS, which on Android is minutes.

That also explains the founder's second observation — *"while loading then
u cancel n click the book again it opens"*. Cancelling does not cancel
anything: `_inFlight` holds the future independently of the screen, so the
download runs on, finishes to disk, and the next tap hits
`if (await file.exists())` and opens instantly from cache.

Now: 15s connect, 20s headers, 60s whole transfer, `.part` always cleaned
up, `client.close(force: true)`.

**Also fixed while in there:** the download never verified `Content-Length`
before renaming `.part` into place, even though `media2.egwwritings.org`
**truncates silently** — the trap the seed script already defends against
(see the `egw-text-source-solved` memory). A short file was cached forever,
failed to parse on every future open, and dropped the member back to the
PDF reader with no explanation. That is a strong candidate for other "the
book won't open" reports.

### NOT FIXED — still open

- [x] **Highlighting in Sabbath School — BUILT 19 Aug. Client is done; the
      migration is NOT applied.** Founder chose (19 Aug) that an SS
      highlight **follows the account**, so unlike EGW's device-local
      store this needed a table.
      - **`database/patch_208_ss_highlights.sql` is written and NOT RUN.**
        Applying it needs a token (§0). Owner-only RLS, one policy per verb
        written out rather than a single `FOR ALL` — `.upsert()` needs
        SELECT *and* INSERT *and* UPDATE to be right, and a missing SELECT
        policy is a trap this project has already hit once. It revokes the
        default `anon` grant by name, because `REVOKE FROM PUBLIC` alone
        leaves anon holding it.
      - `SsHighlights` (`lib/services/ss_highlights_service.dart`) is
        offline-first on purpose: a local mirror paints on the frame the
        member taps, changes queue, and `load()` flushes the queue before
        taking the server's answer — so a highlight made on a bus is not
        erased by the fetch meant to restore it. **Until the patch is
        applied every write simply stays queued**, which is the same code
        path as being offline and is covered by tests.
      - The text rules moved to `lib/services/highlight_text.dart`, shared
        by both readers. `EgwHighlights` delegates to it. Two copies of the
        sentence rule would drift, and that rule is the part most likely to
        be quietly wrong.
      - Pinned by `test/ss_highlights_test.dart` (15 tests) — including the
        renderer half, because the store can be perfect and the feature
        still dead if a tap never reaches it.

- [x] **Sabbath School throws `'_dependents.isEmpty': is not true`** — FIXED
      19 Aug, see above. The diagnosis below was on the right track about
      the mechanism and wrong about the culprit: it is not a `GlobalKey`
      reparent, it is a `TextEditingController` disposed during a route's
      exit transition. Kept for the record.
      (framework.dart:6268). This is an `InheritedElement` being unmounted
      while something still depends on it. It is NOT caused by
      `context.palette` alone — that resolves through `Theme.of`, which
      would throw a different error. Usual causes, in order of likelihood:
      a `GlobalKey` reparented across two subtrees in one frame; a
      `TabController`/`PageController` shared across rebuilt tabs; or a
      dialog/sheet built from a context that has since unmounted. Start by
      grepping `sabbath_school_tab.dart` + `ss_lesson_screen.dart` for
      `GlobalKey` and for any `of(context)` call reached from `dispose()`
      or `deactivate()`. **Reproduce it first** — an assertion with a stack
      trace is the cheapest bug on this list to locate and the easiest to
      "fix" in the wrong place.

      **Narrowed 19 Aug, without a trace** (the founder said "fix" rather
      than fetch one). The assertion is at `framework.dart:6268` in
      `InheritedElement.debugDeactivated()` — read it in the SDK, do not
      guess: it fires when an `InheritedElement` is DEACTIVATED while
      dependents are still registered on it. A dependent removes itself in
      `Element.deactivate()`, so this means the dependent was not
      deactivated along with the subtree it appeared to belong to — the
      textbook cause being a `GlobalKey`'d widget reactivated elsewhere
      rather than torn down.
      What has been ruled out: **there is no `GlobalKey` anywhere in
      `sabbath_school_tab.dart` or `ss_lesson_screen.dart`**, and no
      `of(context)` reached from `dispose()`/`deactivate()`. The
      `AnimatedSwitcher` at `ss_lesson_screen.dart:798` uses a `ValueKey`,
      not a global one.
      Best remaining lead: `_SsDayReaderScreenState._loadDays` disposes
      `_pageCtrl` and builds a new one INSIDE `setState`
      (`ss_lesson_screen.dart:596`), which also swaps the body from a
      spinner to the `PageView` in the same frame.
      **Next step is a reproduction harness, not more reading.**
      `SabbathSchoolService` tries the network and falls back to Hive, and
      `flutter_test` fails HTTP fast — so seeding a box and pumping the real
      screens drives the whole flow offline. Drive it hard: open a lesson,
      swipe days, pop mid-load. An assert that fires in a test comes with
      the stack trace that makes this a ten-minute fix.

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

## 3a. ADS — Appodeal migration + quiz monetisation. DONE 18 Aug, NOT verified on hardware

**AdMob is gone.** `google_mobile_ads` is removed from `pubspec.yaml`;
`stack_appodeal_flutter: 4.2.0` replaces it. 472 tests pass,
`flutter analyze` clean (4 pre-existing infos). **Nothing has run on a
phone** — see "What still needs a device" below, which is the whole
remaining risk.

### What the code looks like now

* `AdConfig` is no longer a registry of ad-unit IDs — Appodeal has none.
  It holds the App Key and a test-mode flag, nothing else.
* `AdsService.init()` configures, attaches callbacks, and calls
  `Appodeal.initialize`. **The premium-before-ads ordering in `main.dart`
  survived untouched**, which was the point: it only ever decided WHETHER
  `AdsService.init()` runs, never which SDK is behind it.
* `discardCachedAds()` is real now: auto-cache off for all four types,
  hide + destroy the banner/MREC views, and `canRequestAds` drops to
  false — which is what actually stops every `show()` in the app.
* **`AppOpenAdManager` is gone** (Appodeal has no App-Open format).
  `ResumeAdManager` replaces it: a capped interstitial on resume that
  **delegates to `InterstitialAdManager`**, so the 2-minute global gap
  applies to it too. Two managers each holding their own cap would have
  shown two full-screen ads back to back.
* The route blocklist moved out of `main.dart` (where it was private and
  untestable) into `ResumeAdManager.blockedPrefixes`.
* **`NativeAdCard` → `FeedAdCard`.** Appodeal's Flutter plugin has no
  native format (`AppodealAdType.NativeAd` is marked "In progress" in the
  SDK's own enum), so the in-feed card is a 300x250 MREC in the app's own
  card chrome with an explicit "Sponsored" label doing the attribution
  Google's native template used to.
* Consent: **removed our UMP flow entirely.** Appodeal 3.0+ bundles the
  Stack Consent Manager and gathers consent during `initialize()`. Running
  both would have asked the same user twice.

### The third surprise, which the brief did not have

The brief listed two (no ad-unit IDs, no App-Open). There is a third, and
it is the one that would have shipped a visible bug:

**Appodeal hands out ONE banner view and ONE MREC view per process.** From
the plugin's own Android source (`AppodealAdView.kt`), both live in static
`WeakReference`s and every new platform view starts with
`(adView.parent as? ViewGroup)?.removeView(adView)`. So a second banner
does not get a second ad — it *rips the view out of the first one*, which
then renders an empty box.

This is reachable in the shipping app: pushing Jobs on top of Home leaves
both routes mounted (Navigator keeps a covered route alive) and both place
a banner.

Two consequences, both already in the code:

1. `AdViewSlot` (`lib/services/ads/ad_view_slot.dart`) arbitrates. Widgets
   claim a slot and render only while their claim is active; the **newest**
   claim wins, because that is the screen the user is looking at, and
   releasing hands the view back to the one underneath. Pinned by
   `test/ad_view_slot_test.dart`.
2. **The in-feed cards are capped at ONE per feed** — Home was 3, Watch
   repeated every 8 videos forever. That is a capacity limit, not a taste
   one: three MREC cards would have meant one ad and two empty gaps.

### Advent Chat carries no ads. Ever.

Founder, 18 Aug: *"chat tab should not get ads n messaging etc all thing
associated with messaging."* This already held — the inbox uses a plain
`Scaffold` with `MainBottomNav` rather than `MainScaffold`, so it never
picked up the default banner — but that was an accident of how the screen
was written, and `MainScaffold.showAd` **defaults to true**. Anyone
converting the inbox to `MainScaffold` "for consistency" would have put
ads in Advent Chat without noticing.

`test/ads_never_in_chat_test.dart` now reads every file under
`lib/screens/messaging/` and fails if any of them so much as imports an ad
widget, and separately asserts `/messages` is still on the full-screen
blocklist.

### Quiz monetisation — what shipped

The premise correction from 17 Aug held up, and one more came out of the
code: **the lifeline chip already switched to a "watch an ad" affordance
when the player couldn't afford it.** That placement was less hidden than
the brief assumed. What was actually missing was everything around it.

Built, all of it purely additive — *nothing in the quiz is gated behind an
ad, and the Daily Challenge is untouched*:

1. **Survival continue.** The run ends by the rules, then offers "Continue
   your run" with "End run" beside it at equal weight and no countdown
   pressuring the choice. Capped at **one per run** — a run that can be
   extended forever is not sudden death, and the leaderboard it feeds stops
   meaning anything. The combo resets, so an ad can never buy a multiplier.
2. **Coin top-up in the lobby** — the "real button, not a silent fallback".
   50 coins.
3. **Streak repair**, once a week. Works because a missed day does *not*
   clear the stored streak — the reset is lazy, computed on the next
   `recordDailyComplete()`. Repair moves the "last played" marker to
   yesterday so the next daily continues instead of resetting. It does not
   invent progress: you still have to play today.
4. **Double your coins at round end** — and the results-screen interstitial
   is **skipped** when that offer is showing, so the player never gets two
   ads on one screen.
5. **Premium gets continues and lifelines free.** They can't watch a
   rewarded ad (they never load an SDK), so charging them coins for what a
   free player can watch for was the wrong way round. The lifeline chip
   says `FREE`. Coin offers are hidden from them entirely — with lifelines
   free, coins buy a subscriber nothing.

**Deliberate change from the brief: it doubles COINS, not points.** Points
feed lifetime totals, personal bests and the shared leaderboard, and
`QuizCloudService.recordRound` has already banked the round by the time the
results screen is up. Doubling them would put an ad-bought score on a board
other members are ranked against. Coins are private in-app currency, so
doubling them is pure upside with nothing to distrust. **Founder should
confirm this call.**

Rules and caps all live in `lib/services/quiz_rewards_service.dart`, pinned
by `test/quiz_rewards_test.dart` (16 tests).

### What still needs a device — the whole remaining risk

Everything below is unverifiable without hardware and none of it is
verified:

- [ ] **A real ad actually filling.** Only BidMachine / Backfill / Ad
      Server Campaigns are live, so expect thin fill at first. Watch for
      `Appodeal` lines in `adb logcat`.
- [ ] **The consent dialog appears once and only once**, and that we are
      not double-prompting.
- [ ] **The banner is 50dp and the MREC 250dp on a real screen.** The frame
      contract is pinned by two tests, but the platform view itself has
      never been laid out.
- [ ] **Scroll the Home and Watch feeds** and confirm the sponsored card
      never leaves an empty gap and never teleports between positions —
      that is what the slot arbitration is there to prevent.
- [ ] **Push Jobs on top of Home** and confirm exactly one banner is
      visible, then pop back and confirm Home's returns.
- [ ] **Resume from background** and confirm at most one interstitial, and
      never over a chat, prayer or auth screen.
- [ ] **A rewarded ad end to end**: the survival continue is the one to
      test, because it is the only placement that changes game state.
- [ ] **APK size.** Only the BidMachine adapter was added; do not paste
      Appodeal's full README dependency list, it is ~70 adapters.

### iOS is NOT done

There is no `ios/Podfile` in the repo at all, so iOS has never been
pod-installed and Appodeal cannot build there. Also note the README's own
Podfile pins **`platform :ios, '15.0'`** (the base SDK claims 13.0, but the
Firebase adapter needs 15.0) — the 17 Aug note that "iOS 13.0 already
clears the floor" is optimistic. iOS stays deferred; see the iOS readiness
item.

### Do not undo these

* **Never add an AdMob adapter** to `android/app/build.gradle.kts`. The
  account is disapproved and under appeal. `AdsService` also calls
  `disableNetwork("admob")` as a second line of defence.
* If one is ever added back, the `com.google.android.gms.ads.APPLICATION_ID`
  meta-data must return to `AndroidManifest.xml` **in the same change** —
  play-services-ads crashes the app on launch without it. The removed tag
  is quoted verbatim in a comment where it used to sit.
* The `heightFactor: 1` banner trap still applies and is still pinned by
  `test/ad_banner_height_test.dart` — `AdBannerFrame` is provider-agnostic
  and the migration did not touch it.

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
