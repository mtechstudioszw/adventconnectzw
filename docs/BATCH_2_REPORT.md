# Batch 2 report — App shell, Home, Marketplace, Profile

Branch `ccr-4c202ed8-wau71m`. Cloud session, 28 Oct 2026.

## Verification

| Check | Result |
|---|---|
| `flutter analyze` (whole app) | **No issues found** (was 3 infos at the Batch 1 baseline; fixed) |
| `flutter test` (whole suite) | **790 passed**, 0 failed |
| New regression tests | 11 files. The widget tests marked † were run against the original code and fail there |
| On a real device | **Not done.** No device or emulator in the cloud session — see "Needs a device" |

## Owner decisions taken (from the local session, carried out here)

- Tabs stay alive (`StatefulShellRoute` + `TabShell`); island unchanged.
- Home order: header → live → Churches/Events/Prayer chips → Stories →
  Today cards → Library chips → Featured church events → feed.
- Composer card removed; floating gold "+" posts. Donate chip → Prayer
  (Donate still in Settings, Android only).

## What changed

### Home
- **Sabbath School card opens today's reading**, not the 13-week list.
  Back steps out day → quarter → shelf. With no reading dated today it
  stays on the list. (`ss_today_index_test`)
- **Offline feed told members they had no friends.** First-page failure
  with nothing cached showed "Your feed starts here — follow a church".
  Now "You're offline" / "Couldn't load your feed" + Try again.
  (`feed_error_card_test`)
- **"Load more" failure** was silent, left a blank gap, and refired on
  every scroll event. Now stops and offers Try again.
- **Featured church events** loaded once per session (keep-alive
  regression) and lost church names in cache. Now paints from cache and
  refreshes with Home. (`event_cache_roundtrip_test`)
- **Left open overnight**, Home kept yesterday's devotion / hymn / track /
  book. Now refreshes on resume when the day changes.
- Unused `ComposerEntry` deleted.

### Marketplace
- **Category race** — a slow earlier category could fill the grid under
  the current chip. (`marketplace_category_race_test` †)
- **Old grid stayed up under a new category**, forever if the load
  failed. Grid area now skeletons while loading; chips stay usable.
- **Search with a comma or bracket returned nothing** — in Marketplace,
  Churches, Directory, Events and Jobs. (`or_filter_value_test`)
- **Shared link to a deleted listing crashed** the details screen;
  seller-removed listings opened as "RESERVED". (`product_details_gone_test` †)
- **Editing a listing dropped subcategory, condition and location** —
  never pre-filled, never saved. (`edit_product_fields_test` †)
- **Daily post-limit message was never shown anywhere** (7 create
  screens said "Please try again"). Now shown.
- **Banned / pending / rejected shops opened for buyers** with their
  products, against the patch_031 rule. (`seller_profile_states_test` †)
- **Checkout could send a shop a duplicate order** when the signal
  dropped between creating the order and reading it back.
  (`checkout_duplicate_order_test` †)
- **Order status updates refused by RLS showed as saved.** Decline /
  Cancel now confirm first. (`order_status_update_test`)
- New posts (job, event, prayer, listing) now appear in their list
  straight away. (`post_fab_on_created_test`)
- "Sign in to save listings" no longer shown to signed-in members who
  are offline.

### Profile
- **Went stale for the whole session** (keep-alive regression): Home said
  "Posted — see it on your profile" and it wasn't there. Refreshes on
  return now (throttled 10s), via new `TabShell.activeIndex`.
- **Own avatar was blurry** for Google sign-ins (96px into a 118dp
  circle; 96px full-screen). Profile and Edit Profile request the right
  size now.
- Profile → Chat still opens the normal conversation (Batch 1 fix; test
  still passing).

### Test infrastructure
- `test/helpers/fake_supabase.dart`: a real Supabase client whose HTTP is
  answered in-test, plus `signInFake()`. Screens that read through the
  static services can now be widget-tested. Six of the new test files
  use it.

## Needs the owner

1. **Run (after review) `database/patch_270_order_status_transitions.sql`.**
   Live DB check: either party can set any order status through the API,
   so a buyer can mark their own order "confirmed" or "completed". The
   patch only allows the transitions the app's buttons already use.
   Draft only — I did not run it.
2. **Supabase region.** CLAUDE.md says Africa (Cape Town). The live
   project `adventconnectzw` is in **eu-central-1 (Frankfurt)**. Moving
   it means a new project and a migration — your call. Either way,
   CLAUDE.md should say what is true.
3. **The repo can't rebuild the database.** `orders`, `order_items`,
   `place_order` and the orders triggers exist live but aren't in
   `database/`. Recommend exporting them into a patch file.
4. **Marketplace scale limit.** Every product load sends every approved
   seller's id in the URL. Fine now; at a few hundred sellers it will
   fail. Proper fix is a view or RLS join (schema change → approval).
5. **Unused `/marketplace/categories` screen** — nothing links to it and
   it ignores the country scope. Recommend deleting it.
6. Still open from Batch 1: run `patch_269`, rotate the App Store
   Connect key if the repo was ever public, on-device music test.

## Needs a device (I could not check these)

- Home → Sabbath School card → today's reading → Back twice.
- Airplane mode on a fresh install: Home shows "You're offline".
- Gold "+" sits above the island and doesn't cover the last post.
- Marketplace: flick categories quickly; turn data off and switch category.
- Post something, then open Profile: the post is there.
- Leave the app open past midnight: Home shows the new day's devotion.

## Not done in Batch 2

- **Card / listing visual pass.** Design judgement needs eyes on the
  running app; I'd rather do it with screenshots from you than guess.
- Watch and Chat tabs have the same keep-alive staleness risk as Profile
  had. Chat is realtime; Watch is Batch 10. `TabShell.activeIndex` is
  the tool for both.
