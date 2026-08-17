# Prompt for the next session

Paste everything below the line.

---

Continue the Advent Connect ZW work.

**The founder's own bug list is the job this session. It is `TODO.md` §2b.
Start there, not with anything else.** He reported eight things on 18 Aug;
one is fixed and seven are diagnosed-but-not-fixed, each written up with the
file, the line, the mechanism and the named suspects. He has said plainly he
expects them addressed. Do not open a new front until they are done.

Read `TODO.md` §2b first, then the `egw-text-source-solved` and
`appodeal-shares-one-ad-view` memories.

## Ask these two before anything else

1. **Has the Supabase personal access token been rotated?** Asked on 18 Aug;
   the answer was *"didnt rotate"*. The 16 Aug PAT and the one used for the
   17 Aug DB work are both still live and both burned. Never reuse a token
   from a transcript — ask for a fresh one, write it only to the session
   scratchpad, never echo it back.
2. **Is a phone connected?** This is now the biggest gap in the project.
   Four of the seven open bugs are things only a human looking at a screen
   can judge. **This machine cannot build Android at all** — see below.

## The seven, in the order I'd take them

1. **`'_dependents.isEmpty': is not true` in Sabbath School.** A crash, and
   the cheapest on the list *if the founder can supply the stack trace*
   (`flutter logs`, or the red screen). **Ask him for it first.** It is an
   `InheritedElement` unmounted while something still depends on it — most
   often a `GlobalKey` reparented across two subtrees in one frame. It is
   NOT `context.palette` on its own; that resolves through `Theme.of`, which
   fails differently.
2. **Text size / Day / Sepia do nothing when tapped.** **Reproduce before
   changing a line.** The obvious fix is the wrong one: the notifier wiring
   is already correct (`egw_reader_screen.dart:192` wraps build in a
   `ValueListenableBuilder` on `EgwReaderPrefs.revision`, and both setters
   bump it). Top suspect is `CacheService.writePref` throwing, which would
   swallow the `setState` after it and freeze the SHEET too — which matches
   "click does nothing" exactly. Second suspect: `showModalBottomSheet`'s
   `backgroundColor` is computed once at call time, so the sheet's own
   ground never changes even when the page behind it does.
3. **Show the book cover while a book opens** ("put the book thumbnail at
   the first when u open book"). Quick, visual, and most of what makes the
   wait feel broken rather than merely slow.
4. **The page-turn animation is too much.** `_turnBy` is 320ms
   `easeOutCubic` plus the `PageView`'s own physics. Cut it hard or drop to
   a straight cut. Standing rule: motion must never cost reading time.
5. **Tap-to-highlight a whole statement.** Tap inside a sentence, highlight
   that sentence, accumulate many. Real work, not a patch — but the storage
   is already on your side: `EgwHighlights` matches by TEXT not offsets, and
   `rangesIn()` already renders multiple passages per block. So it is a
   gesture + sentence-boundary problem. Watch abbreviations and verse
   references when finding the boundary.
6. **Highlighting in Sabbath School at all** — it does not exist there.
   Needs the founder's call: should an SS highlight follow the account, or
   stay on the device like EGW's do?
7. Anything he adds. He reports in batches; expect more.

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

`flutter test` is ~2.5 min. Never run two at once. Never run
`dart format lib/`.
