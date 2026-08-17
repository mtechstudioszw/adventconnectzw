# Advent Connect ZW — open work

Last updated 17 Aug 2026. Ordered by priority. Everything here is either
diagnosed or has a stated unknown — nothing is a guess.

---

## 0. Blocked on the founder (nothing ships until these move)

- [ ] **Rotate the leaked Supabase token.** An `sbp_` PAT was pasted into
      chat on 16 Aug. The previous one was already rotated and now returns
      `Unauthorized`; this one is still live.
- [ ] **Move auth email off Gmail.** `smtp_host` is `smtp.gmail.com`,
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
- [ ] **`churches.members_count` is 0 for all 2,600 rows** — a dead column.
      `follower_count` is the real number and is accurate (only 2 churches
      drift, both overstated by 1). Confirm which one the church card reads;
      if it reads `members_count`, every church shows 0.

## 3. Features requested, not started

- [ ] **EGW reflowable reader + quote cards** — the big one. Founder chose
      options 1+3. Means rendering *text* rather than PDF pages, which is
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
      - [ ] Separately: delete the dead `QuizProfileRequired` path, or make
            the server actually raise it. Right now it is a branch that can
            never run.
- [ ] **Quiz lobby restyle** — founder says it is not premium. No direction
      chosen yet.
- [ ] **Better route into the quiz from Home**, plus what features belong
      there. Open question.
- [ ] **Suggested news** — done (Keep reading rail), listed so it is not
      rebuilt.

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
