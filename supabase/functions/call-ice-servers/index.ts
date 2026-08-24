// =====================================================================
//  Edge Function: call-ice-servers
//
//  Hands a client the ICE servers for ONE call: the free STUN servers,
//  plus a TURN credential that expires in minutes.
//
//  ## Why this exists at all
//
//  A TURN credential is a bandwidth budget. Anyone holding a permanent
//  one can relay arbitrary traffic through the server on our bill, and
//  a credential compiled into the APK is permanent by definition — the
//  APK is public. So nothing here ships in the app: the client asks for
//  credentials at the moment it needs them, proving with its own JWT
//  that it is in a live call, and what it gets back stops working
//  within `call.turn_credential_ttl_seconds` (default 600).
//
//  ## The authorisation is not in this file
//
//  It is `call_may_use_turn(call_id)` in patch_261, and this function
//  calls it WITH THE MEMBER'S OWN TOKEN, not the service role. That is
//  deliberate: the RPC reads auth.uid(), so calling it as service_role
//  would make it answer for nobody and return false — or worse, if it
//  were ever rewritten to take a user parameter, it would answer for
//  whoever the client claimed to be. Passing the JWT through means the
//  database decides, using the same identity the rest of the app uses.
//
//  That RPC also consumes a rate-limit slot (call.rate_ice_max /
//  window), so a client cannot sit in a loop minting credentials.
//
//  ## Providers
//
//  Three modes, chosen by whichever secrets are set. All of them keep
//  the long-lived secret server-side:
//
//    hmac        coturn's REST API (RFC draft), which self-hosted
//                coturn and Metered's static-auth mode both speak.
//                username = "<unix-expiry>:<opaque>", password =
//                base64(HMAC-SHA1(TURN_STATIC_AUTH_SECRET, username)).
//                No network call — the credential is computed here.
//    cloudflare  Cloudflare Realtime TURN. One POST per request.
//    metered     Metered's credential API.
//
//  With none of them configured the function still answers, with STUN
//  only. That is a real, working configuration for most calls — STUN
//  alone succeeds whenever at least one side is not behind a symmetric
//  NAT — it just fails on restrictive mobile networks, which is exactly
//  what TURN is for. The response says which happened in `turn`, and
//  the app surfaces it in the call diagnostics rather than pretending.
//
//  ## What is deliberately NOT here
//
//  The identity in the TURN username is a hash, not the member's id.
//  TURN server access logs are a third-party surface (§40); they get
//  something we can correlate if we have to, and nothing they could
//  resolve to a person on their own.
//
//  Env (set as Edge Function secrets — never committed):
//    TURN_URLS                  comma-separated, e.g.
//                               "turn:turn.example.org:3478?transport=udp,
//                                turns:turn.example.org:5349?transport=tcp"
//    TURN_STATIC_AUTH_SECRET    coturn `use-auth-secret` shared secret
//    TURN_REALM                 optional, informational
//    CLOUDFLARE_TURN_KEY_ID     Cloudflare Realtime TURN key id
//    CLOUDFLARE_TURN_API_TOKEN  its API token
//    METERED_API_KEY            Metered API key
//    METERED_SUBDOMAIN          e.g. "adventconnect" for
//                               adventconnect.metered.live
//    TURN_IDENTITY_SALT         optional; salts the username hash
//    SUPABASE_URL / SUPABASE_ANON_KEY   auto-injected
//
//  Deploy:  supabase functions deploy call-ice-servers
//
//  Runs on Deno. @ts-nocheck silences VS Code's Node-flavoured checker,
//  which knows nothing about `Deno.*` or URL imports.
// =====================================================================

// @ts-nocheck

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const fail = (code: string, status: number) => json({ error: code }, status);

// Google's public STUN. Free, no account, and the only thing in this
// response that is not scoped to one call — a STUN server learns a
// reflexive address and nothing else, which is why handing it out
// unauthenticated is fine.
const STUN_SERVERS = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
];

function b64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.byteLength; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha1Base64(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return b64(new Uint8Array(sig));
}

interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

/// coturn / Metered static-auth. Computed locally — no network hop, so
/// this path adds nothing to call setup time.
async function hmacCredentials(
  ttlSeconds: number,
  identity: string,
): Promise<IceServer[] | null> {
  const secret = Deno.env.get("TURN_STATIC_AUTH_SECRET");
  const urlsRaw = Deno.env.get("TURN_URLS");
  if (!secret || !urlsRaw) return null;

  const urls = urlsRaw.split(",").map((u) => u.trim()).filter(Boolean);
  if (urls.length === 0) return null;

  const expiry = Math.floor(Date.now() / 1000) + ttlSeconds;
  const username = `${expiry}:${identity}`;
  const credential = await hmacSha1Base64(secret, username);

  return [{ urls, username, credential }];
}

async function cloudflareCredentials(
  ttlSeconds: number,
): Promise<IceServer[] | null> {
  const keyId = Deno.env.get("CLOUDFLARE_TURN_KEY_ID");
  const token = Deno.env.get("CLOUDFLARE_TURN_API_TOKEN");
  if (!keyId || !token) return null;

  const resp = await fetch(
    `https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ttl: ttlSeconds }),
    },
  );
  if (!resp.ok) {
    console.error(`call-ice-servers: cloudflare ${resp.status}`);
    return null;
  }
  const data = await resp.json();
  // Cloudflare answers with { iceServers: {...} } (singular object) or
  // an array depending on API version. Normalise both.
  const ice = data?.iceServers;
  if (!ice) return null;
  return Array.isArray(ice) ? ice : [ice];
}

async function meteredCredentials(): Promise<IceServer[] | null> {
  const apiKey = Deno.env.get("METERED_API_KEY");
  const subdomain = Deno.env.get("METERED_SUBDOMAIN");
  if (!apiKey || !subdomain) return null;

  const resp = await fetch(
    `https://${subdomain}.metered.live/api/v1/turn/credentials?apiKey=${
      encodeURIComponent(apiKey)
    }`,
  );
  if (!resp.ok) {
    console.error(`call-ice-servers: metered ${resp.status}`);
    return null;
  }
  const data = await resp.json();
  return Array.isArray(data) ? data : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return fail("unauthenticated", 401);

  let body: { call_id?: string };
  try {
    body = await req.json();
  } catch {
    return fail("bad_request", 400);
  }
  const callId = (body.call_id ?? "").trim();
  if (!/^[0-9a-fA-F-]{36}$/.test(callId)) return fail("bad_request", 400);

  // The member's OWN client — anon key plus their token — so the RPC
  // below runs as them. See the header for why service_role is wrong
  // here.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  const user = userData?.user;
  if (userErr || !user) return fail("unauthenticated", 401);

  const { data: allowed, error: rpcErr } = await supabase.rpc(
    "call_may_use_turn",
    { p_call: callId },
  );
  if (rpcErr) {
    console.error(`call-ice-servers: rpc failed: ${rpcErr.message}`);
    return fail("server_error", 500);
  }
  // False covers both "not in this call" and "asked too many times".
  // One answer for both, so probing tells an attacker nothing.
  if (allowed !== true) return fail("not_allowed", 403);

  // TTL comes from app_config so it can be tuned without a deploy.
  // Read with the member's own token; app_config is world-readable.
  let ttl = 600;
  const { data: cfg } = await supabase
    .from("app_config")
    .select("value")
    .eq("key", "call.turn_credential_ttl_seconds")
    .maybeSingle();
  const parsed = Number.parseInt(cfg?.value ?? "", 10);
  if (Number.isFinite(parsed) && parsed >= 60 && parsed <= 86400) ttl = parsed;

  // Opaque, stable, and correlatable by us if a TURN log ever needs
  // tying to an incident. Scoped per (user, call) so one leaked
  // credential is one call's worth of relay, not a member's whole life.
  const identity = (await sha256Hex(
    `${user.id}:${callId}:${Deno.env.get("TURN_IDENTITY_SALT") ?? "advent"}`,
  )).slice(0, 24);

  let turn: IceServer[] | null = null;
  let provider = "none";
  try {
    turn = await hmacCredentials(ttl, identity);
    if (turn) provider = "hmac";
    if (!turn) {
      turn = await cloudflareCredentials(ttl);
      if (turn) provider = "cloudflare";
    }
    if (!turn) {
      turn = await meteredCredentials();
      if (turn) provider = "metered";
    }
  } catch (e) {
    // A TURN provider being down must not stop the call being ATTEMPTED
    // — most calls connect without relay. Fall through to STUN only.
    console.error(`call-ice-servers: provider error: ${(e as Error).message}`);
    turn = null;
    provider = "error";
  }

  return json({
    ice_servers: [...STUN_SERVERS, ...(turn ?? [])],
    // The client logs this into call_events so "why did that call fail"
    // has an answer. It is a provider NAME, never a credential.
    turn: provider,
    expires_in: ttl,
  });
});
