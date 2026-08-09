# Advent Connect ZW — 1.3.1 (build 1033)

**Released:** 4 August 2026
**Previous production version:** 1.3.0

This is the first release with **Premium** live and proven with a real
purchase, and it closes out a large backlog of bugs found during a
same-day security audit and device-testing pass.

---

## Premium subscription — LIVE

- $3/month, ad-free, auto-renewing. Product `premium_monthly`, base plan
  `monthly`, priced across 174 countries/regions.
- Verified end-to-end with a real purchase: `subscriptions` row written,
  `profiles.premium_until` set correctly, ads gated off.
- RTDN wired: cancellations and refunds now correctly revoke premium via
  Google Pub/Sub → Supabase Edge Function, confirmed live with Play's
  test notification.
- Fixed: the purchase-verification error message used to say "couldn't
  reach the server" for every failure, including ones where the server
  had answered just fine. It now reports what actually happened.

## Security

- **Every DELETE in the app was silently doing nothing** since an
  earlier patch — unlike, unfriend, deleting a post/comment/message,
  leaving a group, cancelling an RSVP. Fixed at the database level;
  already live for all current users, no update required.
- Closed a hole where any member could self-grant the gold "verified"
  tick.
- Closed an unauthenticated push-notification endpoint that could have
  let anyone send fake notifications to any member.
- Closed two fail-open edge functions that skipped authentication
  entirely when a secret was left unconfigured.
- Removed the `ACCESS_FINE_LOCATION` permission — the app only ever
  needed coarse accuracy for "nearby churches."
- Added abuse-rate limits on posts, comments, friend requests, reports,
  stories and messages (generous ceilings — this is anti-abuse, not a
  paywall).
- Freed ~198MB of database log bloat and added nightly pruning so it
  doesn't return.

## Fixed

- **Sign out did nothing when tapped** — it actually worked every time,
  but the screen never navigated away afterward, so it looked broken.
- Chat privacy settings had never loaded, for anyone, due to a missing
  database grant.
- Quiz background music was inaudible on some devices — it was declared
  using the wrong Android audio stream.
- The devotion verse on Home was getting cut off mid-sentence at larger
  text sizes.
- Playing music offline with no downloaded copy gave a confusing raw
  error instead of a plain explanation.
- Editing ministry involvement / spiritual gifts while offline failed
  silently after the member had already done the work.

## Changed

- Music and Watch mini-players are now draggable, resizable, and
  mutually exclusive — opening one closes the other so they don't play
  over each other.
- The "What would you like to share?" screen redesigned around Post and
  Story as primary, everything else as secondary rows.
- Quiz Arena: background music now plays for the whole session (lobby
  through results), not just mid-round; the sound settings button moved
  from the loading screen (gone in ~1s) to the lobby, where it's
  reachable.
- A short ad now plays while the Quiz Arena loads.
- Quiz coin earn rate roughly halved going forward — existing balances
  untouched.
- "Meet people" at the end of the feed now opens Find People instead of
  a broken screen.
- Main search field redesigned to match the chat search field.

---

*Full technical detail and the reasoning behind each change is in the
commit history on `main` — every commit from `000d494` through `008fa34`
is part of this release.*
