# Prompt for the next session

Paste everything below the line.

---

Continue the Advent Connect ZW work.

Read `TODO.md` §3a first — the ads migration landed on 18 Aug and that
section is now a **device checklist**, not a plan. Then the
`appodeal-migration-and-quiz-ads` and `appodeal-shares-one-ad-view`
memories. `TODO.md` overall is the live queue and carries the evidence
behind every item.

## Do this before anything else

**Ask whether the Supabase personal access token has been rotated.** It was
asked on 18 Aug and the answer was *"didnt rotate"* — so the 16 Aug PAT and
the one used for the 17 Aug DB work are both still live and both burned. Do
not reuse a token from any transcript. Ask for a fresh one, write it only to
the session scratchpad, never echo it back.

**Ask whether a phone is connected.** This is now the single biggest gap.

## The state of the ads work

**AdMob is gone.** `google_mobile_ads` is out of `pubspec.yaml`;
`stack_appodeal_flutter: 4.2.0` is in. 472 tests pass, `flutter analyze` is
clean (4 pre-existing infos). The quiz rewarded placements are built too.

**None of it has run on a phone.** That is the whole remaining risk, and
TODO §3a has the checklist. The items that matter most:

* a real ad filling at all (only BidMachine / Backfill / Ad Server
  Campaigns are live, so expect thin fill);
* the consent dialog appearing **once**;
* the banner at 50dp and the MREC at 250dp on a real screen — the frame is
  pinned by tests but the platform view has never been laid out;
* scrolling Home and Watch and confirming the sponsored card never leaves a
  gap or teleports;
* pushing Jobs on top of Home: **exactly one banner**, and Home's returns
  when you pop back;
* a rewarded ad end to end — the survival continue, because it is the only
  placement that changes game state.

Two founder decisions are outstanding:

1. **Paste the Appodeal `app-ads.txt` block** from the dashboard into both
   `docs/app-ads.txt` and `legal-site/app-ads.txt`. A comment is already
   waiting for it. Until it is there, demand partners' bids get filtered —
   a revenue blocker.
2. **Confirm the double-coins call.** The brief said "double your points";
   it doubles **coins** instead, because points feed personal bests and the
   shared leaderboard and the round is already banked by the time the
   results screen shows. Reasoning is in TODO §3a.

## Still open, NOT ads

* **Church posting identity** — posting as a church uses the ADMIN's name,
  not the church's; events unverified. Not started.
* **Offline popup on other screens** — Home has `showOfflineToast`; the
  founder wanted the same elsewhere. Not started.
* **Dead `QuizProfileRequired` branch** — verified unreachable against
  production. Note that `QuizProfileSheet` itself is NOT dead and deleting
  it breaks two features.
* **Highlight sync** — EGW highlights are device-local, so they are lost on
  sign-out and do not follow a member to a new phone. Needs the founder's
  call on a table + RLS.
* **Church admin dashboard** — the founder's own open question: what else
  belongs there?
* **iOS** — there is **no `ios/Podfile` in the repo at all**, so Appodeal
  cannot build there. Appodeal's own Podfile pins `platform :ios, '15.0'`,
  so the earlier "13.0 already clears the floor" note is optimistic.

## How to work here

The repo is a **nested clone**: working directory
`C:\Users\j\Desktop\advent_connect_zw`, repo in `adventconnectzw/`.

Rules that keep earning their place:

1. **Check whether it already exists before building it.** It caught one
   again on 18 Aug: the quiz lifeline chip already switched to a "watch an
   ad" affordance when the player couldn't afford it, so half of "the quiz
   isn't serving ads properly" was a diagnosis problem, not a build one.
2. **Read the plugin's own source, not just its README.** The one genuinely
   dangerous fact about Appodeal — that there is a single shared banner
   view per process — is not in the docs. It is in `AppodealAdView.kt`.
3. **Verify against the DB, a test, or a render — never by reading code.**
4. **Renders work with no device** — a throwaway `matchesGoldenFile` test
   plus `--update-goldens`. Delete the temp test and `test/renders/` after.
   Call `AppTextStyles.applyBrightness()` first or every screen renders
   navy-on-navy and you will report a bug that does not exist.
5. **Pump every screen at 1.6x and 2.5x text scale.** An unflexed `Text` in
   a `Row` THROWS.
6. **A route name is just a string until someone taps it.**
7. **Only the UI isolate may refresh auth tokens.**
8. **A shared guard being fixed does not mean its callers were.**
9. **`REVOKE FROM public` is not enough** — Supabase grants EXECUTE to anon
   and authenticated by name. Verify with `has_function_privilege`.

`flutter test` is ~2.5 min. **A test that sleeps a fixed number of
milliseconds waiting for an async chain is a flake, not a regression** —
`billing_service_test.dart` had a flat 20ms `settle()` racing a
secure-storage write with no plugin behind it, and it went red on 18 Aug
looking exactly like the ads work had broken billing. It now polls until
the flow leaves its in-flight states. Check `git status` on the files a
failing test actually depends on before believing it is yours. Never run
two `flutter test` processes at once. Never run `dart format lib/`.
