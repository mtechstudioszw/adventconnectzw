# Prompt for the next session

Paste everything below the line.

---

Continue the Advent Connect ZW work. **This session is the ADS session.**

Read `TODO.md` §3a first — it is the whole brief, credentials included.
Then the `appodeal-migration-and-quiz-ads` memory. `TODO.md` overall is the
live queue and carries the evidence behind every item.

## Do this before anything else

**Confirm the Supabase personal access token has been rotated.** One was
pasted into chat on 17 Aug and used for that session's DB work, so it is
burned. Do not reuse a token from a transcript — ask for a fresh one, write
it only to the session scratchpad, never echo it back. (The Appodeal *app
key* in TODO §3a is different: it ships inside every APK and is not a
secret.)

## The job: AdMob → Appodeal

AdMob is out — **the account AND the app were disapproved**, so fill is zero
today regardless of code. Provider chosen: **Appodeal**,
`stack_appodeal_flutter: 4.2.0`. The app's minSdk (24) and iOS target (13.0)
already clear its floors.

Two things that will surprise you, both confirmed against the founder's own
dashboard:

1. **There are no ad unit IDs.** Initialise with the App Key, request by
   TYPE; Appodeal runs the waterfall. Nothing gets pasted into code. This is
   the opposite of the AdMob model.
2. **There is no App-Open format.** So `AppOpenAdManager` has no equivalent
   and must become an interstitial-on-resume or be dropped — and if it
   becomes an interstitial it must inherit `_appOpenBlockedPrefixes` from
   `main.dart`.

**The invariant that must survive:** `main.dart:134-157` resolves premium
BEFORE ads, so a subscriber never initialises an ad SDK at all. That is
provider-agnostic — keep the new init inside `AdsService.init()`, keep
surfaces gating on `canRequestAds`, and give `discardCachedAds()` a real
implementation.

Also in scope: **quiz monetisation.** The founder wants more rewarded
revenue and proposed lives-that-reset. I advised against gating scripture in
a church app and offered additive placements instead (survival continue,
double points, explicit coin top-up, streak repair). He agreed to revisit.
Full reasoning in TODO §3a — read it before designing.

## Still open, NOT ads

The founder said "nothing left besides ads" — that is not quite right, and
these should not be lost:

* **Church posting identity** — posting as a church uses the ADMIN's name,
  not the church's; events unverified. Not started.
* **Offline popup on other screens** — Home has `showOfflineToast`; the
  founder wanted the same elsewhere. Not started.
* **Dead `QuizProfileRequired` branch** — verified unreachable against
  production (zero functions contain it). Scoped in TODO; note that
  `QuizProfileSheet` itself is NOT dead and deleting it breaks two features.
* **Highlight sync** — EGW highlights are device-local, so they are lost on
  sign-out and do not follow a member to a new phone. Needs the founder's
  call on a table + RLS.
* **Church admin dashboard** — the founder's own open question: what else
  belongs there?

## Needs a device — the biggest gap

**Nothing from 17 Aug has run on real hardware.** `adb devices` is empty and
`flutter devices` shows only Windows/Chrome/Edge. The EGW reader, its page
turns, the dark-mode fixes, the Home quiz surfaces and the church header are
all verified by golden render and test only. Ads in particular cannot be
finished without a device.

The DB half IS verified against production: 61/61 EPUBs byte-checked in
storage, 61/61 rows carrying `epub_url`, patch_206 and patch_207 applied and
their grants checked.

## How to work here

The repo is a **nested clone**: working directory
`C:\Users\j\Desktop\advent_connect_zw`, repo in `adventconnectzw/`.

Rules that keep earning their place:

1. **Check whether it already exists before building it.** Ten+ "missing"
   features this month were built and quietly broken. It catches wrong
   diagnoses too: the quiz already serves rewarded ads, and the church
   `members_count` "bug" was not the dead column at all.
2. **Verify against the DB, a test, or a render — never by reading code.**
3. **Renders work with no device** — a throwaway `matchesGoldenFile` test
   plus `--update-goldens`. Delete the temp test and `test/renders/` after.
   Call `AppTextStyles.applyBrightness()` first or every screen renders
   navy-on-navy and you will report a bug that does not exist.
4. **Pump every screen at 1.6x and 2.5x text scale.** An unflexed `Text` in
   a `Row` THROWS. It caught a real 105px overflow again on 17 Aug.
5. **A route name is just a string until someone taps it.**
6. **Only the UI isolate may refresh auth tokens.**
7. **A shared guard being fixed does not mean its callers were.**
8. **`REVOKE FROM public` is not enough** — Supabase grants EXECUTE to anon
   and authenticated by name. Verify with `has_function_privilege`.

`flutter test` is ~2.5 min. **The suite flakes** — a single failure that
does not reproduce on a clean re-run is a flake, not a regression; it
happened four times on 17 Aug and never twice on the same test. Never run
two `flutter test` processes at once. Never run `dart format lib/`.

State at handover: **446 tests passing**, `flutter analyze` clean (4
pre-existing infos), **nothing committed** — 45 files changed, 19 new.
