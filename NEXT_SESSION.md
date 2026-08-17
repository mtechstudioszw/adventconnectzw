# Prompt for the next session

Paste everything below the line.

---

Continue the Advent Connect ZW work.

**Read `TODO.md` in the repo root first — it is the live queue and carries
the evidence behind every item.** Then read the `open-queue-aug16`,
`founder-batch-aug17` and `background-isolate-revoked-the-session` memories.

## Do these two things before anything else

1. **Confirm the Supabase personal access token has been rotated.** One was
   pasted into chat on 17 Aug and is still live as far as I know. Do not use
   a token from a transcript — ask for a fresh one, write it only to the
   session scratchpad, and never echo it back.
2. **Ask whether auth email has been moved off Gmail.** `smtp_host` is
   `smtp.gmail.com` with `rate_limit_otp: 30/hr`. The founder's two reports —
   "codes are getting spammed" and "it's not sending the reset code" — are
   the SAME event an hour apart: the spam exhausts the limit and legitimate
   resets then fail. Nothing else in the app explains it. This is the highest
   -impact open item and it needs a provider decision.

## What is already designed and just needs building

Three quiz decisions were made and NOT implemented. Directions are chosen —
do not re-ask:

- **Lobby → "Daily Challenge hero + quiet modes."** Today's challenge
  dominates with the streak; the other five modes become a quiet list. Keep
  the dark arena canvas; only hierarchy changes.
- **Home → BOTH** a Daily Challenge card in the Today slot (taps straight
  into the questions, skipping the lobby) AND a live dot on the existing Quiz
  pill for "someone wants you".
- **Live match must be discoverable from Home.** The founder's sharpest point
  of the session: it is two taps deep behind a tile, which is most of why
  only ~11 members have ever played one. It is the only real-time
  person-to-person feature in the app. `PresenceService.onlineUsers` and
  `QuizMatchService.invites()` already exist — only the Home surface is
  missing.

The **EGW reflowable reader + quote cards** is the largest untouched item and
was requested three times. **Do not start it by writing UI.** The books are
PDFs and a reflowable reader needs text, so establish the text source first:
probe the egwwritings.org API against the 61 seeded titles, and test
extraction on two or three of the existing PDFs. Show the founder samples of
both before committing. Building on the wrong source wastes days.

## Two things needing one detail from the founder

- **"The church screen full screen is cut out."** Ask which screen and what
  is cut — the 16:9 cover, the full-image viewer when the logo is tapped, or
  content behind the floating nav. A screenshot settles it.
- **Ad mediation.** The founder is choosing a new provider. See TODO §3b —
  the AdMob account is disapproved and under appeal, `docs/app-ads.txt` holds
  the publisher authorisation Google crawls, and `main.dart` deliberately
  resolves premium BEFORE ads so subscribers never start the SDK.

## Pending action that needs a release

`app_config.quiz_ready_check` is **`off`**. The live-match ready check is
fully built, server and client, but build 12 has never heard of the `ready`
status and would poll forever. After a build carrying the client half ships:

    UPDATE public.app_config SET value = 'on' WHERE key = 'quiz_ready_check';

Likewise `app_events` stays at 0 until a build with the analytics UUID fix
reaches users — do not build the admin dashboard over an empty table.

## How to work here

The repo is a **nested clone**: the working directory is
`C:\Users\j\Desktop\advent_connect_zw`, the repo is in `adventconnectzw/`.

Rules that repeatedly earned their place, most recently by catching my own
mistakes:

1. **Check whether it already exists before building it.** TEN "missing"
   features turned out to be built and quietly broken. It catches wrong
   diagnoses too — I claimed a quiz "name gate" that does not exist.
2. **Query with an authenticated context, not the anon key.** Several tables
   are `TO {authenticated}` and read as empty otherwise. Use
   `set_config('request.jwt.claims', …)` + `set local role authenticated`.
3. **Verify against the DB, a test, or a render — never by reading code.**
   No device is attached, but renders still work: a throwaway
   `matchesGoldenFile` test plus `--update-goldens` writes a PNG you can
   look at. Delete the temp test and `test/renders/` afterwards.
4. **Pump every screen at 1.6x and 2.5x text scale.** That caught two real
   overflows in one session, one of them pre-existing across all four legal
   screens.
5. **A route name is just a string until someone taps it.** Two dead routes
   were found this month. `appRouter.configuration.namedLocation('x')` in a
   unit test catches them.
6. **Only the UI isolate may refresh auth tokens.** A second GoTrue client
   revokes the app's own refresh token and signs the member out of a session
   that is alive on the server.
7. **A shared guard being fixed does not mean its callers were.** Some
   "callers" are inline copies that never called it — that is how blocked
   users stayed visible after `is_blocked_by()` was made symmetric.

`flutter test` is ~2 minutes and safe. Never run `dart format lib/` — it
rewrites 240+ untouched files. Do not run two `flutter test` processes at
once; it makes the billing test flake.

State at handover: **358 tests passing**, `flutter analyze` clean (4
pre-existing infos), sixteen commits pushed to `main`, patches 201–205 live
and verified, nothing half-applied.
