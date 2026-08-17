# Prompt for the next session

Paste everything below the line.

---

Continue the Advent Connect ZW work.

**Two things are left of the founder's EGW / Sabbath School batch, and both
are Sabbath School.** Everything else in `TODO.md` §2b is done and pushed.
Read §2b first — it now records the one bug that was behind five separate
reports, and the rule that came out of it.

## Ask these two before anything else

1. **Has the Supabase personal access token been rotated?** Asked 18 Aug
   (*"didnt rotate"*) and again 19 Aug. Both burned tokens are still live.
   **This now blocks real work**, not just tidiness: the founder decided SS
   highlights follow the ACCOUNT, which needs a table + RLS. Never reuse a
   token from a transcript — ask for a fresh one, write it only to the
   session scratchpad, never echo it back.
2. **Is a phone connected?** Answered "no" on 19 Aug, and it is still the
   biggest gap in the project. **This machine cannot build Android at all**
   — see below. Everything shipped on 19 Aug was reproduced and pinned with
   widget tests instead, which worked well, but four earlier items were only
   ever judged by reading code.

## What is left, in the order I'd take them

1. **Apply `database/patch_208_ss_highlights.sql`.** Sabbath School
   highlighting is BUILT and tested — the client works offline today and
   queues every write. The table does not exist yet, so nothing has reached
   an account. This is the first thing to do once a token arrives, and the
   patch has its own VERIFY block at the bottom: four policies, `anon`
   without SELECT, `authenticated` with it.
2. **`app-ads.txt` is still not published** — see §0. The file in the repo
   is right; what is SERVED at the domain root is a single stale AdMob line.
   Revenue stays blocked until that changes, and it is a founder action.
3. **"there no shelf"** — his one report from 19 Aug still unresolved, and
   genuinely ambiguous. Ask; do not guess. §2b has both readings.
4. Anything he adds. He reports in batches; expect more.

**The Sabbath School crash is FIXED** — his own repro ("click the pencil
icon n click back") was the whole diagnosis. It was never a `GlobalKey`
reparent: a `TextEditingController` was disposed the line after
`await showModalBottomSheet`, which returns when the route is POPPED, not
when it has finished LEAVING. Pinned, and verified red against the old code.

## What shipped 19 Aug (do not redo any of it)

* **The CI build was broken and had been since the Appodeal migration** —
  manifest merger, `allowBackup`. Every "the last build failed" report
  traces to this. Fixed in `5115a48`.
* **One bug was behind five reports**: a Hive write awaited before the
  notifier that repaints. Reading settings, save-to-shelf and the download
  tick all looked dead because of it. **New standing rule: never `await`
  storage before the notifier that repaints.** `writePref` reaches Hive's
  in-memory keystore before its first `await`, so a same-frame read already
  sees the new value.
* **`EgwDownloadService.download` had no timeout of any kind** — the same
  bug fixed in `EgwBookService` on 18 Aug, in the twin it was written to
  mirror. Only one half got the fix. **When you fix a service that says it
  mirrors another, go and check the other one.**
* Tap-to-turn removed, page curl cut from ~99° to ~29°, cover shown while a
  book opens, and tap-a-sentence-to-highlight built and tested.
* **Pull-to-refresh was broken across the whole Library**, not just EGW:
  `setState(() => _future = future)` is an arrow body, so it RETURNS the
  Future it assigns, and `setState` asserts against that. Eight call sites.
  A debug apk throws on every pull.
* **The Sabbath School red screen** — a `TextEditingController` disposed
  during a route's exit transition. Two more instances of the same shape
  fixed alongside it (`prayer_circles_sheet`, `church_admin_approvals`).

**Three of the day's bugs were one-line mistakes with no compiler or
analyzer signal at all** — an arrow body that returned a value, an `await`
that resolved earlier than it looked, and a notify that came after a disk
write. `flutter analyze` was clean through every one of them. Reproducing
before fixing is what found all three; do not skip it.

## What shipped 18 Aug (do not redo any of it)

* **AdMob → Appodeal**, complete. `google_mobile_ads` is gone. The
  premium-before-ads ordering in `main.dart` needed no changes.
* **Quiz rewarded placements** — survival continue, lobby coin top-up,
  weekly streak repair, double-coins at round end. All additive; nothing is
  gated behind an ad and the Daily Challenge is untouched.
* **The live-match strips stopped lying.** They were fed the APP-WIDE
  presence roster and printed "N online now · play someone".
* **`app-ads.txt` is installed** — 2,514 records, both copies. Revenue
  unblocked.
* **EGW book download now times out** (it had none at all) and verifies
  `Content-Length` before caching.
* Home library chips reordered; live-match strip moved above the live video.

**480 tests pass, `flutter analyze` clean (4 pre-existing infos), everything
committed and pushed to `main`.**

## Two founder decisions still open

* **Double-coins vs double-points** at quiz round end. It doubles COINS
  deliberately — the round is already banked on the shared leaderboard by
  then, so doubling points would put an ad-bought rank in front of other
  members. He has not confirmed.
* **A truthful "N waiting in the arena"** needs a server-side count of open
  queue entries — an RPC, so it is blocked on the token.

## How to work here

Nested clone: working directory `C:\Users\j\Desktop\advent_connect_zw`, repo
in `adventconnectzw/`.

1. **`flutter build apk` on this machine is a DEAD END.** Three attempts,
   ~12 minutes, all dying in Gradle *project evaluation* on corrupt
   transform caches — deleting the 1.1GB cache does not help, the next run
   corrupts fresh hashes. It never reaches the app's own config, so **a
   failed local build tells you nothing about your change**. Push and let
   `.github/workflows/build-apk.yml` build it. Founder's instruction:
   *"let github build."* `gh` is not installed here.
2. **A red CI run is often the upload step, not the build.** The
   `softprops/action-gh-release` step hits transient GitHub 5xx *after* a
   successful build. Read which step failed before believing the code broke.
3. **Check whether it already exists before building it.** It caught one on
   18 Aug: the quiz lifeline chip already switched to a "watch an ad"
   affordance when the player could not afford it.
4. **Read the plugin's source, not just its README.** The one dangerous fact
   about Appodeal — a single shared banner view per process — is in
   `AppodealAdView.kt`, not the docs.
5. **Verify against the DB, a test, or a render — never by reading code.**
   Renders work with no device: a throwaway `matchesGoldenFile` test plus
   `--update-goldens`. Call `AppTextStyles.applyBrightness()` first or every
   screen renders navy-on-navy.
6. **Pump every screen at 1.6x and 2.5x.** An unflexed `Text` in a `Row`
   THROWS.
7. **A route name is just a string until someone taps it.**
8. **`CacheService.writePref` does NOT add the `pref:` prefix** — without it
   sign-out eats the key. Relevant to bug #2 above.
9. **A test that sleeps a fixed number of ms waiting on an async chain is a
   flake, not a regression.** `billing_service_test` had a flat 20ms
   `settle()` and went red looking exactly like the ads work had broken
   billing. Check `git status` on the files a failing test depends on before
   believing it is yours.
10. **Never paste a large file into chat** — it truncates silently at ~50k
    chars. The founder's app-ads.txt was cut at a third and it looked
    complete. Have him save files to the repo instead.
11. **A test that leaves a Hive write outstanding must not close the box in
    teardown.** `testWidgets` runs in a fake-async zone; a write started
    there never completes, and `Hive.deleteFromDisk()` waits on the write
    queue forever. The file then sits out the TEN-MINUTE test timeout and
    looks like a hang rather than failing assertions — it cost most of an
    hour on 19 Aug. Use a fresh box NAME per test and just detach.
    `test/egw_reader_settings_test.dart` documents the pattern.
12. **`Builder(...).findRenderObject()` returns the nearest descendant
    render object, which is NOT necessarily the one you want.** Wrapping a
    `Text` in a `GestureDetector` puts the detector's own render object in
    the way, so a hit-test for a character offset silently found nothing.
    Descend to the `RenderParagraph` explicitly.
13. **When output looks empty, suspect the pipe, not the process.**
    `flutter test ... | Select-Object -Last N` buffers everything until the
    command exits, and a parent `dart` process idling at flat CPU while
    workers run looks exactly like a wedge. Both cost real time on 19 Aug.

`flutter test` is ~2.5 min. Never run two at once. Never run
`dart format lib/`.
