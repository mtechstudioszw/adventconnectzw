# Calls — status and plan

## UPDATE 1 Nov 2026 (later): calling is BUILT again — Android first

Owner: "implement the call system until it's finished". Done as follows:

- **Restored, not rewritten.** The full client deleted in commit 1ec0043
  is back, about 7,000 lines plus 144 tests: CallService, the mesh WebRTC
  transport, signalling, CallKit bridge, call screen, call history and
  the admin metrics. It was written against this exact backend, so
  restoring it was safer than rewriting.
- **Root cause of "no call ever connected", fixed.**
  - Accepting on the lock screen with the app closed launched the app,
    but the plugin's accept event fired before Dart was listening, and
    it was lost.
  - The app then saw the call still "ringing" and rang a second time.
    The caller gave up, and the call was logged callee-missed /
    caller-cancelled. That was 32 of the 35 real attempts.
  - The fix: on start, `CallKitBridge.acceptedCallIds()` reads the
    native `isAccepted` flag (which the Dart wrapper drops) and joins
    the call straight away.
- **Android manifest fixed.** The phone-call and microphone
  foreground-service permissions were being *removed*. On Android 14+
  that kills the call service, so the phone cannot ring or keep the
  microphone. They are restored, and the service is narrowed to
  phoneCall|microphone.
- **iPhone: hidden (`kHideCalls`).** CallKit/PushKit has never been
  compiled for iOS, and the VoIP/audio background modes were removed
  after App Review. Turn it on later, together with an APNs VoIP key.

Owner steps before members use it:
1. **TURN (needed on mobile data).**
   - Cloudflare dashboard → Realtime → TURN → create a key.
   - Set the Supabase secrets `CLOUDFLARE_TURN_KEY_ID` and
     `CLOUDFLARE_TURN_API_TOKEN`.
   - No redeploy is needed; `call-ice-servers` reads them on each call.
2. **Play Console → App content → Full-screen intent:** declare
   "calling".
3. **Two-phone test:** follow the checklist in §8 of
   docs/CALLING_SETUP.md, especially calling a phone whose app is fully
   closed.

---

# Original plan (written before the build)

Owner, 1 Nov 2026: *"don't build it yet … just organize it … talk about it."*
This is that. Nothing here has been built. `docs/CALLING_SETUP.md` is the
older technical reference for the backend that already exists.

---

## 1. Where we actually are

**Backend: done, live, and sound.** In Supabase today:

- Tables `calls`, `call_participants`, `call_events`, `call_usage_daily`,
  `user_call_devices`.
- ~45 `call_*` RPCs, including start, accept, reject, join, leave,
  heartbeat, end, history, preflight, reachability, daily/monthly caps and
  sweeping stale calls.
- Edge functions `call-ice-servers` (short-lived TURN credentials) and
  `call-push` (VoIP push on iOS, data push on Android).
- 36 `call.*` settings in `app_config`:
  - Calling is on.
  - Free tier: 120 min/day, 1,500 min/month.
  - Groups: up to 5 people.
  - A call can only be made between friends, or once the other person
    has replied.
  - Ring timeout 60 s.

**App: deleted.** The calling screens were removed because they were buggy
and would not connect.

**The evidence, measured 1 Nov 2026:** 35 calls were attempted. **None ever
connected.**

| How it ended | Count |
|---|---|
| cancelled | 19 |
| busy | 9 |
| missed | 4 |
| rejected | 3 |

So the problem was never the database. It was everything between two
phones.

### Why it didn't connect (most likely, in order)

1. **No TURN server configured, or not reachable.**
   - Most Zimbabwean mobile data sits behind carrier-grade NAT.
   - Phone-to-phone WebRTC without a TURN relay fails for a large share
     of calls on those networks; they ring, then never get audio.
   - **Check first:** are `TURN_URLS` / `TURN_STATIC_AUTH_SECRET` (or the
     Cloudflare / Metered keys) set on `call-ice-servers`?
2. **The "busy" results.** Nine calls (a quarter) ended "busy". With
   `call.max_concurrent_calls = 1`, a previous call that never closed
   properly makes the next one look busy. `call_sweep_stale` exists, but
   it must actually run on a schedule; check that it does.
3. **Incoming calls when the app is closed.** Waking a closed app to ring
   needs:
   - Android: a full-screen-intent notification through ConnectionService.
   - iOS: CallKit + PushKit.

   Without these, the callee only ever "misses" a call. That matches the
   missed and cancelled rows.

---

## 2. The decision you need to make (my recommendation first)

| Option | What it is | Cost | Honest verdict |
|---|---|---|---|
| **A. Keep peer-to-peer + add Cloudflare TURN** *(recommended)* | Our backend as-is, `flutter_webrtc` in the app, Cloudflare Realtime TURN for relays | **Free up to 1,000 GB/month**, then $0.05/GB. A voice call relayed costs ~22 MB/hour, so the free tier covers about **45,000 relayed call-hours a month** | Cheapest. Uses everything already built. Group calls stay capped at 5 |
| B. Managed SFU (LiveKit Cloud) | Their servers mix the call | Free tier small; then per-minute | More reliable for groups, but it throws away half our backend and adds a monthly bill |
| C. Agora / Twilio | Fully managed SDK | Per minute, from the first minute | Fastest to ship, most expensive, data leaves to a US vendor |

**My recommendation: A.** The authority plane, the limits and the push
function are already written and reviewed. Only the media path and the
ringing UI are missing, and Cloudflare's free tier is far beyond our
size (the app has ~700 members).

---

## 3. Build order (when you say "build it")

**Step 1 — TURN.** Create a Cloudflare Realtime TURN key and set it on
`call-ice-servers`. Test it from two phones on different mobile networks
(Econet ↔ NetOne), one of them on mobile data. *0.5 day.*

**Step 2 — 1:1 voice only, app open.**
- `flutter_webrtc` (exact version pinned).
- One call screen: avatar, name, timer, mute, speaker, end.
- Signalling over the existing private Realtime topic.
- Heartbeat every 15 s.
- **Ship gate:** 20 test calls in a row connect, including over relay.
  *2–3 days.*

**Step 3 — Ringing when the app is closed.** *3–4 days. The hard part.*
- **Android:** a full-screen incoming-call notification and
  ConnectionService (e.g. `flutter_callkit_incoming`).
- **iOS:**
  - CallKit + PushKit. `call-push` already sends `apns-push-type: voip`.
  - Apple *requires* that every VoIP push shows CallKit immediately, or
    it revokes the app's VoIP pushes.

**Step 4 — Call history tab and missed-call notifications.**
`call_history` already exists. *1 day.*

**Step 5 — Groups (up to 5).** Mesh is already modelled server-side.
*2 days, after 1:1 is stable for two weeks.*

**Step 6 — Video.** *Not recommended this year.*
- Video uses about 20× the data of voice.
- It is the first thing members on expensive bundles will notice.

**Total for steps 1–4: about 8–10 working days.**

---

## 4. Things to decide or know before building

- **Premium:** calling minutes already have Plus/Pro caps in config. If
  Premium stays hidden on iOS, iPhone users all get the free cap. That is
  fine, but say so in the App Store notes.
- **Apple review:** CallKit apps get extra scrutiny. Calls must work for
  the reviewer, so the demo account needs a friend to call.
- **Privacy policy:** add a line saying calls are peer-to-peer and
  encrypted in transit (DTLS-SRTP), relays only pass encrypted audio, and
  nothing is recorded.
- **Data cost to members:** about 0.4 MB a minute for voice. Show it once
  on the first call.

---

# Stories — end-to-end encryption plan (no code yet)

## Why stories are harder than chat

**A chat message has a fixed set of readers. A story is broadcast** to
"my friends" or "everyone", and that audience changes after posting:
- someone is friended or unfriended;
- someone joins the app.

Signal-style encryption needs the list of readers at the moment of
encryption.

## Options

| Option | How | Verdict |
|---|---|---|
| **1. Encrypt friends-only stories** *(recommended)* | Same as group chat: a per-author *Sender Key*, given to each friend over their existing 1:1 encrypted session. The story photo/video is sealed with a per-story AES key (exactly what photos in chat now use), and that key is wrapped with the sender key | Works with what we built this week. A new friend can't see stories from before they were friends, which is the right privacy outcome anyway |
| 2. Encrypt "everyone" stories | Impossible to do honestly. A public story is meant for strangers; encrypting it to "everyone" means giving everyone the key | Don't. Label public stories as public |
| 3. Encrypt nothing, rely on private storage | Today's state | Fine until E2EE is advertised for stories |

## Build order (when approved)
1. Turn E2EE on for chat first (`patch_295`), after the two-phone test.
   Watch it for two weeks.
2. Add a sender-key distribution for "my friends" stories, reusing the
   group-chat code path in `E2eeService`.
3. Seal story media with `MediaCrypto` (already written and tested for
   chat photos and voice notes).
4. Mark public stories clearly as public in the composer.

**Estimate: 3–4 days after chat E2EE has been stable.**

## Honest limits

- No key backup yet. A reinstall loses the ability to read stories
  received before it, the same as chat history.
- Moderation:
  - Reported stories must send the decrypted copy, the way messages do
    with `report_message p_text_copy`.
  - Without that, nobody can review a reported encrypted story.
