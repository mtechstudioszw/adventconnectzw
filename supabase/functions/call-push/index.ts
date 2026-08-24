// =====================================================================
//  Edge Function: call-push
//
//  Rings ONE member's devices for ONE call, or tells them to stop.
//
//  Called by a database trigger (patch_263), never by a client. The
//  body is {call_id, user_id, action} and the caller proves itself with
//  `x-call-secret`, which lives in Supabase Vault on the database side
//  and as the CALL_PUSH_SECRET env var here.
//
//  ## Why this is not notify-fcm
//
//  notify-fcm turns a `notifications` row into a display notification.
//  An incoming call is not an inbox item and cannot be a display
//  notification:
//
//    * It must be DATA-ONLY and HIGH priority so the device wakes the
//      app and renders a full-screen call UI, not a banner.
//    * It must expire. A push that arrives four minutes late must not
//      ring a phone for a call that finished three minutes ago, so
//      every message carries a TTL of the remaining ring time.
//    * On iOS it must be an APNs **VoIP** push. FCM cannot send one:
//      Apple requires the `<bundle-id>.voip` topic and
//      `apns-push-type: voip`, and FCM only ever publishes to the
//      app's normal topic. So this function talks to APNs directly.
//
//  ## What is in the payload
//
//  The caller's name and photo, the call id and kind, and the room
//  token is DELIBERATELY ABSENT. The token is the signalling capability
//  (patch_260) and a push is the least private thing in the system — it
//  passes through Google and Apple and can sit in a notification log.
//  The device fetches the token itself with `call_current()` once it is
//  awake and authenticated.
//
//  Env (Edge Function secrets — never committed):
//    CALL_PUSH_SECRET          matches the `call_push_secret` Vault row
//    FCM_SERVICE_ACCOUNT_JSON  Firebase service account (shared with
//                              notify-fcm — same project, same key)
//    APNS_AUTH_KEY_P8          contents of the AuthKey_XXXX.p8 file
//    APNS_KEY_ID               that key's 10-character id
//    APNS_TEAM_ID              Apple Developer team id
//    APNS_BUNDLE_ID            e.g. io.supabase.adventconnectzw.advent_connect_zw
//    APNS_ENV                  "production" | "sandbox"  (default sandbox)
//    SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   auto-injected
//
//  The APNS_* set requires a paid Apple Developer account. Until those
//  are configured this function still rings Android correctly and logs
//  one line per skipped iOS device — it does not fail the request, and
//  it does not pretend to have delivered anything.
//
//  Deploy:  supabase functions deploy call-push --no-verify-jwt
//  (--no-verify-jwt because the caller is Postgres, not a signed-in
//  user; the x-call-secret check below is the authentication.)
//
//  Runs on Deno. @ts-nocheck silences VS Code's Node-flavoured checker.
// =====================================================================

// @ts-nocheck

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

// ---------- small helpers --------------------------------------------

function base64Url(input: string | Uint8Array): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let s = "";
  for (let i = 0; i < bytes.byteLength; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

/// Constant-time compare, so the secret cannot be recovered a byte at a
/// time by timing the 401. Same posture as notify-fcm.
function secretOk(supplied: string | null): boolean {
  const expected = Deno.env.get("CALL_PUSH_SECRET") ?? "";
  // FAIL CLOSED. A missing env var means we cannot authenticate anyone,
  // which is a reason to refuse, not to wave everyone through — that is
  // precisely the idiom that left play-rtdn open.
  if (expected.length === 0 || supplied === null) return false;
  const a = new TextEncoder().encode(supplied);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// ---------- FCM (Android) ---------------------------------------------

// Google access tokens last an hour. Minting one per push would add a
// round trip to every ring and burn quota, so it is cached in module
// scope with a minute of headroom.
let googleToken: { token: string; expiresAt: number } | null = null;

async function fcmAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (googleToken && googleToken.expiresAt > now + 60) return googleToken.token;

  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: FCM_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  const jwt = `${header}.${payload}.${base64Url(new Uint8Array(sig))}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) throw new Error(`google token ${resp.status}`);
  const json = await resp.json();
  if (!json.access_token) throw new Error("google token: no access_token");
  googleToken = { token: json.access_token, expiresAt: now + 3300 };
  return json.access_token;
}

async function sendFcm(
  account: ServiceAccount,
  token: string,
  data: Record<string, string>,
  ttlSeconds: number,
): Promise<boolean> {
  const accessToken = await fcmAccessToken(account);
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token,
          // DATA ONLY. A `notification` block would make the system draw
          // a banner and would NOT wake the background isolate that
          // builds the full-screen incoming-call UI.
          data,
          android: {
            priority: "HIGH",
            // Past this the call is over; a late ring is worse than none.
            ttl: `${Math.max(1, ttlSeconds)}s`,
          },
        },
      }),
    },
  );
  if (!resp.ok) {
    console.error(`call-push: fcm ${resp.status}: ${await resp.text()}`);
    return false;
  }
  return true;
}

// ---------- APNs VoIP (iOS) -------------------------------------------

// Apple rejects a token refreshed more often than once per 20 minutes
// and expects one no older than an hour. 45 minutes sits safely between.
let apnsToken: { token: string; issuedAt: number } | null = null;

async function apnsJwt(): Promise<string | null> {
  const p8 = Deno.env.get("APNS_AUTH_KEY_P8");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!p8 || !keyId || !teamId) return null;

  const now = Math.floor(Date.now() / 1000);
  if (apnsToken && now - apnsToken.issuedAt < 2700) return apnsToken.token;

  const header = base64Url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = base64Url(JSON.stringify({ iss: teamId, iat: now }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(p8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto returns ES256 signatures as raw r||s, which is exactly
  // the JWS encoding — no DER unwrapping needed.
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  const jwt = `${header}.${payload}.${base64Url(new Uint8Array(sig))}`;
  apnsToken = { token: jwt, issuedAt: now };
  return jwt;
}

async function sendApnsVoip(
  deviceToken: string,
  payload: Record<string, unknown>,
  ttlSeconds: number,
): Promise<boolean> {
  const jwt = await apnsJwt();
  const bundle = Deno.env.get("APNS_BUNDLE_ID");
  if (!jwt || !bundle) {
    // Not an error: iOS simply is not configured yet. Said plainly once
    // per attempt rather than swallowed, so "iPhones never ring" has an
    // answer in the logs.
    console.log("call-push: APNs not configured; skipping iOS device");
    return false;
  }
  const host = (Deno.env.get("APNS_ENV") ?? "sandbox") === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const resp = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      // The VoIP topic is the bundle id with `.voip` appended — a
      // different topic from the one FCM publishes to, which is why
      // this cannot go through FCM.
      "apns-topic": `${bundle}.voip`,
      "apns-push-type": "voip",
      "apns-priority": "10",
      "apns-expiration": `${Math.floor(Date.now() / 1000) + Math.max(1, ttlSeconds)}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!resp.ok) {
    console.error(`call-push: apns ${resp.status}: ${await resp.text()}`);
    return false;
  }
  return true;
}

// ---------- handler ----------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  if (!secretOk(req.headers.get("x-call-secret"))) {
    console.error("call-push: rejected a call with a missing/invalid secret");
    return new Response("Unauthorized", { status: 401 });
  }

  let body: { call_id?: string; user_id?: string; action?: string };
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const callId = (body.call_id ?? "").trim();
  const userId = (body.user_id ?? "").trim();
  const action = body.action === "cancel" ? "cancel" : "ring";
  if (!callId || !userId) return new Response("Missing fields", { status: 400 });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // The call itself, so the payload can name the caller. service_role
  // bypasses RLS here on purpose — the trigger authenticated this call,
  // not a user, so there is no auth.uid() to read through.
  const { data: call } = await supabase
    .from("calls")
    .select("id, kind, status, created_by, conversation_id, ring_expires_at")
    .eq("id", callId)
    .maybeSingle();
  if (!call) return new Response("No such call", { status: 200 });

  // A ring for a call that is already over is dropped here rather than
  // on the device. Cancels are always delivered — that IS the "it is
  // over" message.
  if (action === "ring" && call.status === "ended") {
    return new Response("Call already ended; ring skipped", { status: 200 });
  }

  // TTL = whatever is left of the ring. A push that outlives the call
  // is how a phone ends up ringing for nothing.
  const ringEnds = Date.parse(call.ring_expires_at ?? "") || Date.now();
  const ttl = action === "cancel"
    ? 60
    : Math.max(1, Math.min(180, Math.round((ringEnds - Date.now()) / 1000)));
  if (action === "ring" && ttl <= 1) {
    return new Response("Ring window closed", { status: 200 });
  }

  const { data: caller } = await supabase
    .from("profiles")
    .select("full_name, profile_photo_url")
    .eq("id", call.created_by)
    .maybeSingle();

  let title = (caller?.full_name ?? "").trim() || "Adventist Super App";
  if (call.kind === "group" && call.conversation_id) {
    const { data: convo } = await supabase
      .from("conversations")
      .select("name")
      .eq("id", call.conversation_id)
      .maybeSingle();
    const groupName = (convo?.name ?? "").trim();
    if (groupName) title = `${title} · ${groupName}`;
  }

  const { data: devices } = await supabase
    .from("user_call_devices")
    .select("platform, voip_token, push_token")
    .eq("user_id", userId);

  if (!devices || devices.length === 0) {
    // Nowhere to ring. The call still rings in-app for a member who has
    // the app open (Realtime), and rings out into a missed call
    // otherwise — which is the honest outcome, not a failure.
    return new Response("No registered devices", { status: 200 });
  }

  // Every value must be a string: FCM v1 rejects a data map otherwise.
  const data: Record<string, string> = {
    type: "call",
    action,
    call_id: String(call.id),
    call_kind: String(call.kind),
    caller_id: String(call.created_by),
    caller_name: title,
    caller_photo: (caller?.profile_photo_url ?? "") as string,
    // Milliseconds left, so the device can arm its own dismissal timer
    // without trusting its clock against ours.
    ttl_ms: String(ttl * 1000),
  };

  let account: ServiceAccount | null = null;
  try {
    const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
    if (raw) {
      account = JSON.parse(raw) as ServiceAccount;
      if (!account.client_email || !account.private_key || !account.project_id) {
        account = null;
      }
    }
  } catch {
    account = null;
  }

  let delivered = 0;
  for (const device of devices) {
    try {
      if (device.platform === "ios" && device.voip_token) {
        const ok = await sendApnsVoip(device.voip_token, {
          // PushKit payloads are free-form; the AppDelegate reads these
          // keys directly (see ios/Runner/AppDelegate.swift).
          ...data,
          aps: { "content-available": 1 },
        }, ttl);
        if (ok) delivered++;
      } else if (device.platform === "android" && device.push_token) {
        if (!account) {
          console.error("call-push: FCM_SERVICE_ACCOUNT_JSON missing/invalid");
          continue;
        }
        const ok = await sendFcm(account, device.push_token, data, ttl);
        if (ok) delivered++;
      }
    } catch (e) {
      // One dead device must not stop the others being rung.
      console.error(`call-push: device ${device.platform}: ${(e as Error).message}`);
    }
  }

  return new Response(
    JSON.stringify({ delivered, devices: devices.length, action }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
