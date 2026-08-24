# Audio calling — setup, cost and operations

Voice calls (1:1 and small group) for the Adventist Super App.

**Read this before turning calling on in production.** The code is
complete; what is *not* complete is the infrastructure it needs, and one
piece of that (TURN) costs money and has to be chosen by a person.

---

## 1. Architecture

Three planes, deliberately kept apart.

| Plane | Runs on | Carries |
|---|---|---|
| **Authority** | Postgres (patches 260–264) | Who is in a call, what state it is in, when it connected, how long it ran, who is allowed to call whom |
| **Signalling** | Supabase Realtime *private* broadcast, topic `call:<room_token>` | SDP offers/answers, ICE candidates, mute and speaking flags. Never written to a table |
| **Media** | WebRTC, phone→phone (TURN-relayed only when the network forces it) | The audio. Never touches Supabase |

Every state transition goes through a `SECURITY DEFINER` RPC. The client
cannot assert that a call connected, that it lasted twenty minutes, or
that someone joined — it asks, and the database decides.

### No audio is recorded

There is no column, no bucket and no code path that stores call audio.
`call_events.detail` is a diagnostics bag with a **key whitelist** (see
`call_log_event` in patch_261) precisely so a future "let's just log the
payload" change cannot start storing SDP, which carries device IP
addresses. Recording calls would be a product and legal decision with a
disclosure requirement — not a schema tweak.

### `room_token` is a capability

`calls.room_token` is a random UUID and it *is* the Realtime topic. It is
handed out only by `call_join`/`call_snapshot`, and only while the
member's participant row is live. Never log it, never put it in a push
payload, never derive it from the call id. The push function
deliberately omits it — the device fetches it with `call_current()` once
it is awake and authenticated.

---

## 2. Why mesh, and when to stop

Each phone sends its own Opus stream to every other phone. At N
participants the uplink is (N−1) × ~24 kbps:

| Participants | Uplink per phone | Verdict |
|---|---|---|
| 2 (1:1) | ~24 kbps | Ideal. Audio never touches a server we pay for |
| 3 | ~48 kbps | Fine anywhere |
| **5** | **~96 kbps** | **The configured ceiling** |
| 8 | ~168 kbps | Starts failing on a busy 3G cell; 7 encoders on a mid-range phone |
| 12 | ~264 kbps | Not viable on this app's device profile |

`call.max_group_participants` is **5**, enforced server-side in
`call_start` (the `LIMIT` on the invite loop is what makes it unforgeable
— a client cannot ask for more).

### Raising it needs an SFU, not a bigger number

`lib/services/calls/call_transport.dart` defines a 7-method interface:
`start`, `setPeers`, `handleSignal`, `setMuted`, `restartIce`, `stats`,
`dispose`, plus `events` and `aggregateState`. `MeshCallTransport`
implements it. An SFU implementation would implement the same interface
and **nothing above that line changes** — `CallService` and every screen
are unaware of how many peer connections exist, or whether there are any.

Realistic options, in rough order of effort:

- **LiveKit Cloud** — managed SFU, generous free tier, drop-in.
- **LiveKit self-hosted** — one Go binary; a small VPS handles dozens of
  concurrent audio participants.
- **mediasoup** — Node library, most control, most work.
- **Janus** — mature C SFU, heavier to operate.

⚠️ **Re-check pricing yourself.** Do not trust figures quoted in this
document or by an assistant; RTC providers change their terms.

---

## 3. External dependencies

| Service | Required? | What happens without it |
|---|---|---|
| **Supabase** (patches 260–264) | ✅ Yes | Nothing works. Already applied |
| **TURN provider** | ⚠️ Strongly | Calls connect when at least one side is not behind a symmetric NAT; **fail on restrictive mobile networks**. This is the one that costs money |
| **FCM** | ✅ Yes, Android | Already configured (shared with `notify-fcm`). Android rings today |
| **APNs VoIP** | ✅ Yes, iOS | **Not configured.** iPhones never ring when the app is closed. Needs a paid Apple Developer account |
| **`CALL_PUSH_SECRET`** | ✅ Yes | `call-push` returns 401 and **no phone ever rings** |

### 3.1 TURN

`call-ice-servers` supports three modes, picked by whichever secrets are
set. All keep the long-lived secret server-side and mint credentials that
expire in `call.turn_credential_ttl_seconds` (default 600).

| Mode | Secrets |
|---|---|
| `hmac` (coturn, and Metered's static-auth) | `TURN_URLS`, `TURN_STATIC_AUTH_SECRET`, `TURN_REALM` (optional) |
| `cloudflare` | `CLOUDFLARE_TURN_KEY_ID`, `CLOUDFLARE_TURN_API_TOKEN` |
| `metered` | `METERED_API_KEY`, `METERED_SUBDOMAIN` |

`TURN_IDENTITY_SALT` (optional) salts the hash used as the TURN username,
so TURN access logs — a third-party surface — hold something we can
correlate but nobody else can resolve to a person.

With none set the function still answers, with STUN only, and reports
`"turn": "none"`. That is a real working configuration for most calls,
not a failure mode — it just loses the hard networks.

**Cheapest path — self-hosted coturn** (any small VPS):

```conf
# /etc/turnserver.conf
listening-port=3478
tls-listening-port=5349

# REST-API mode. The shared secret never leaves the server; the Edge
# Function computes credentials from it and they expire in minutes.
use-auth-secret
static-auth-secret=<long random string — same value as TURN_STATIC_AUTH_SECRET>
realm=turn.yourdomain.org

# Audio only: no need for a wide range.
min-port=49152
max-port=49500

fingerprint
no-multicast-peers
no-cli

# TLS (get certs from Let's Encrypt). turns: on 5349 is what gets through
# corporate and hotel networks that block UDP.
cert=/etc/letsencrypt/live/turn.yourdomain.org/fullchain.pem
pkey=/etc/letsencrypt/live/turn.yourdomain.org/privkey.pem
```

Then:

```
TURN_URLS=turn:turn.yourdomain.org:3478?transport=udp,turns:turn.yourdomain.org:5349?transport=tcp
TURN_STATIC_AUTH_SECRET=<the same long random string>
TURN_REALM=turn.yourdomain.org
```

Open UDP/TCP 3478, TCP 5349, and UDP 49152–49500 in the firewall.

### 3.2 APNs VoIP (iOS)

FCM **cannot** send a VoIP push — Apple requires the `<bundle-id>.voip`
topic and `apns-push-type: voip`, and FCM only publishes to the app's
normal topic. So `call-push` signs its own ES256 JWT and talks to Apple
directly.

| Secret | Where it comes from |
|---|---|
| `APNS_AUTH_KEY_P8` | Contents of the `AuthKey_XXXXXXXXXX.p8` file (Apple Developer → Keys → new key with APNs enabled) |
| `APNS_KEY_ID` | That key's 10-character id |
| `APNS_TEAM_ID` | Apple Developer team id |
| `APNS_BUNDLE_ID` | `io.supabase.adventconnectzw.advent_connect_zw` |
| `APNS_ENV` | `sandbox` for development builds, `production` for TestFlight/App Store |

Also flip `aps-environment` in `ios/Runner/Runner.entitlements` to
`production` for release builds, or incoming calls silently never arrive
on TestFlight.

**The iOS code is complete and inert, not missing.** Until these secrets
exist, `call-push` logs one line per skipped iOS device and rings Android
normally.

---

## 4. Deployment runbook

1. **Patches.** 260 → 261 → 262 → 263 → 264, in order.
   *Already applied to project `eqbyvasteolqyktbqbem` on 24 Aug 2026.*
   Verification queries are in the trailing comment block of each file —
   run them and read the output.

2. **Vault secret** (what the database uses to authenticate itself to
   `call-push`):

   ```sql
   select vault.create_secret('<long random string>', 'call_push_secret');
   -- rotate later with:
   -- select vault.update_secret(id, '<new value>') from vault.secrets
   --  where name = 'call_push_secret';
   ```

3. **Edge Function secrets** — the other half of that, plus TURN:

   ```bash
   supabase secrets set CALL_PUSH_SECRET='<the same long random string>'
   supabase secrets set TURN_URLS='...' TURN_STATIC_AUTH_SECRET='...'
   # iOS, once the Apple account exists:
   supabase secrets set APNS_KEY_ID='...' APNS_TEAM_ID='...' \
     APNS_BUNDLE_ID='io.supabase.adventconnectzw.advent_connect_zw' \
     APNS_ENV='sandbox'
   supabase secrets set APNS_AUTH_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
   ```

   `FCM_SERVICE_ACCOUNT_JSON` is already set for `notify-fcm` and is
   shared.

   ⚠️ **A `CALL_PUSH_SECRET` that does not match the Vault row means
   every ring is a 401 and no phone ever rings.** It is the first thing
   to check if calls work in-app but not when the app is closed.

4. **Deploy:**

   ```bash
   supabase functions deploy call-ice-servers
   supabase functions deploy call-push --no-verify-jwt
   ```

   `--no-verify-jwt` on `call-push` is correct and deliberate: the caller
   is **Postgres via pg_net**, not a signed-in user, so there is no JWT to
   verify. It authenticates with the `x-call-secret` header instead,
   compared in constant time and **failing closed** when the env var is
   unset. `call-ice-servers` keeps JWT verification — it must run as the
   member so `call_may_use_turn` can read `auth.uid()`.

5. **Android Play Console.** Declare `USE_FULL_SCREEN_INTENT` and the
   `phoneCall` + `microphone` foreground-service types. Play grants
   full-screen intent to apps that provide calling; this app qualifies.

---

## 5. Every tunable

All live in `app_config`. Changing one is an `UPDATE` and takes effect on
the **next call** — no deploy, no app update, no Play review.

```sql
update public.app_config set value = '60' where key = 'call.ring_timeout_seconds';
```

| Key | Default | Meaning |
|---|---|---|
| `call.enabled` | `true` | Master switch. `false` hides every call button and refuses every `call_start` |
| `call.ring_timeout_seconds` | `45` | How long a phone rings before the call is marked missed |
| `call.connect_timeout_seconds` | `45` | How long to wait for **media** after answering before failing |
| `call.max_group_participants` | `5` | The mesh ceiling (§2) |
| `call.max_direct_call_minutes` | `120` | Hard ceiling on a 1:1 |
| `call.max_group_call_minutes` | `90` | Hard ceiling on a group call |
| `call.free_daily_minutes` | `120` | Free-tier daily quota |
| `call.free_monthly_minutes` | `1500` | Free-tier monthly quota |
| `call.premium_daily_minutes` | `360` | Premium daily quota |
| `call.premium_monthly_minutes` | `4500` | Premium monthly quota |
| `call.max_concurrent_calls` | `1` | A second inbound call is answered `busy` |
| `call.rate_attempts_max` / `_window` | `10` / `600` | Call attempts per member per 10 min |
| `call.rate_per_recipient_max` / `_window` | `3` / `600` | Attempts at the **same** person per 10 min |
| `call.rate_unanswered_max` / `_window` | `20` / `3600` | Unanswered attempts per hour |
| `call.rate_group_create_max` / `_window` | `6` / `3600` | Group calls started per hour |
| `call.rate_group_invite_max` / `_window` | `30` / `3600` | Group invites per hour |
| `call.rate_join_max` / `_window` | `10` / `60` | Join attempts per minute (stops leave/join cycling) |
| `call.rate_signal_max` / `_window` | `600` / `60` | Signalling messages per minute |
| `call.rate_ice_max` / `_window` | `30` / `600` | TURN credential mints per 10 min |
| `call.heartbeat_seconds` | `15` | How often a live call reports in |
| `call.stale_grace_seconds` | `75` | Silence after which the sweeper kills a call |
| `call.require_friend_or_reply` | `true` | A stranger cannot make your phone ring — mirrors the 3-message chat cap |
| `call.turn_credential_ttl_seconds` | `600` | Lifetime of a minted TURN credential |

These are **abuse and cost ceilings, not a product tier.** Do not
repurpose them as something Premium lifts — selling the removal of a spam
limit gives the app a reason to want the limit to bite.

---

## 6. Cost model

**The only per-minute infrastructure cost is TURN relay bandwidth.**

- A peer-to-peer leg costs **nothing** — the audio goes phone to phone.
- Supabase Realtime messages: a few hundred per call (SDP + batched ICE),
  negligible at this scale.
- `pg_net` calls: one per participant per ring, plus the sweeper's
  once-a-minute tick.
- Postgres rows: a handful per call.

### Estimating the TURN bill

Opus is tuned to ~24 kbps (see `_tuneOpus` in `mesh_call_transport.dart`,
which also enables DTX so silence costs almost nothing):

```
24 kbps ÷ 8 = 3 KB/s
3 KB/s × 60 = 180 KB/min ≈ 0.18 MB per minute, per direction
```

A **fully relayed** 10-minute 1:1 call therefore moves roughly
`0.18 × 2 × 10 ≈ 3.6 MB` through TURN. These are estimates — real
traffic includes RTP/UDP overhead and varies with packet loss.

Most calls are not relayed at all. The measurable proxy is:

```sql
-- Relayed minutes per day: the closest thing to a TURN bill without
-- instrumenting coturn itself.
select day,
       round(sum(relayed_seconds) / 60.0, 1) as relayed_minutes,
       round(sum(seconds)         / 60.0, 1) as total_minutes
  from public.call_usage_daily
 where day >= current_date - 30
 group by day
 order by day desc;
```

`relayed` is self-reported by the device from `RTCPeerConnection.getStats()`
and is **telemetry only** — nothing is authorised on it. A client can lie
about it; a client cannot use it to get anything.

---

## 7. Known limitations

**a. Signalling sender identity is not cryptographically verified.**
Supabase Realtime broadcast attaches no verified sender, so the `from`
field is a *claim*. RLS (patch_262) proves the sender is *a* live
participant of that call; it does not prove they are *the* participant
they say they are.

The blast radius is bounded to people **already inside the call** —
nobody reaches the channel without the server having put them in the
room, so this cannot leak audio to an outsider. What it could do is let
one participant disrupt another's connection by impersonating a third.
Two defences are in place (`CallService._onSignal`): every signal is
dropped unless `from` is a participant the *server* reports as joined,
and an `offer` for an established connection is ignored unless it arrives
as an explicit `renegotiate`. Closing the gap properly needs signed
signalling payloads — a real change, deliberately not half-done.

**b. No call waiting.** A second inbound call while you are on one is
answered `busy` by the server. The brief asked for the simple reliable
behaviour first; call waiting needs hold/resume across the whole media
stack.

**c. iOS has never been compiled.** This project is developed on Windows
and there is no Apple Developer account. `AppDelegate.swift`, the
Podfile, the entitlements and the Info.plist keys are written against the
current contracts but are **unverified**. Treat the first iOS build as
the real test.

**d. Groups cap at 5** (§2).

**e. Play Console declarations** are required for `USE_FULL_SCREEN_INTENT`
and the foreground-service types (§4.5).

---

## 8. Real-device testing checklist

**Emulators are not sufficient.** They share a host network stack, so
they never exercise NAT traversal, TURN fallback, carrier handover, or
the Doze/background restrictions that break calls in the field.

Minimum: two physical Android phones on **different carriers**.

### Connectivity
- [ ] Wi-Fi ↔ Wi-Fi (same network)
- [ ] Wi-Fi ↔ Wi-Fi (different networks/buildings)
- [ ] Wi-Fi ↔ mobile data
- [ ] Mobile ↔ mobile, **different carriers** (this is the one TURN exists for)
- [ ] Hand over Wi-Fi → mobile *mid-call* — expect "Reconnecting…", then recovery, **not** a hang-up
- [ ] Airplane mode on for ~10s mid-call, then off
- [ ] Weak signal / far from the router

### Lifecycle
- [ ] App foregrounded
- [ ] App backgrounded during a call — audio must continue
- [ ] Screen locked during a call
- [ ] Incoming call with the app **fully killed** (swipe from recents first)
- [ ] Incoming call on a **locked** phone — full-screen UI over the lock screen
- [ ] Force-quit mid-call, reopen — must not leave a ghost call (`call_current` recovery)
- [ ] Caller cancels while the callee's phone is still ringing — ringing must stop

### Controls
- [ ] Mute / unmute (confirm the other side actually stops hearing you)
- [ ] Speaker on/off
- [ ] Earpiece
- [ ] Bluetooth headset — connect before the call, and connect *during* a call
- [ ] Unplug wired headphones mid-call (must fall back, not go silent)
- [ ] Call timer starts at **connect**, not at ring

### Outcomes
- [ ] Answered → both hang up cleanly
- [ ] Declined
- [ ] Rang out → missed-call entry on both sides, exactly one
- [ ] Callee already on another call → caller sees "on another call"
- [ ] Both sides' call history agrees

### Group
- [ ] 3, 4 and 5 participants
- [ ] A participant joins an in-progress call
- [ ] A participant leaves — call continues for the rest
- [ ] Host ends for everyone
- [ ] Two people join simultaneously
- [ ] A 6th person is refused (cap)
- [ ] Host removes a participant

### Security and limits
- [ ] Blocked user cannot call — and gets the *same* message as any other refusal
- [ ] Non-friend with no chat history cannot ring you (`call.require_friend_or_reply`)
- [ ] Non-member cannot join a group call
- [ ] 4th call to the same person inside 10 minutes is refused
- [ ] 11th call attempt inside 10 minutes is refused
- [ ] Daily quota exhaustion blocks a *new* call and does not kill a live one
- [ ] Kill a phone's network without hanging up → the sweeper ends the call within ~90s

### Cleanup
- [ ] Microphone indicator goes out the moment a call ends
- [ ] Music that was playing before the call resumes afterwards
- [ ] No stuck "active" rows: `select * from calls where status <> 'ended' and started_at < now() - interval '1 hour';` returns nothing
