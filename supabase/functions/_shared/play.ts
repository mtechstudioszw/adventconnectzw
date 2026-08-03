// =====================================================================
//  Shared Google Play Developer API helpers.
//
//  Used by BOTH verify-purchase (client asks us to confirm a purchase)
//  and play-rtdn (Google tells us a subscription changed). Keeping the
//  state mapping in one place is the point: the two paths must agree on
//  what "active" means, or a renewal and a verification would disagree
//  and premium would flicker.
//
//  Required secret:
//    GOOGLE_PLAY_SA_JSON — the full service-account JSON key, as one
//    string. Create it in Google Cloud Console, grant it Play Developer
//    API access, then invite it in Play Console → Users & permissions
//    with "View financial data" + "Manage orders and subscriptions".
//    NEVER commit it or paste it into chat; set it with
//      supabase secrets set GOOGLE_PLAY_SA_JSON="$(cat key.json)"
//    or via the dashboard.
// =====================================================================
// @ts-nocheck

export const PLAY_PACKAGE_NAME =
  Deno.env.get("PLAY_PACKAGE_NAME") ??
  "io.supabase.adventconnectzw.advent_connect_zw";

/// Our own status vocabulary — matches the CHECK constraint on
/// public.subscriptions exactly.
export type SubStatus =
  | "pending"
  | "active"
  | "in_grace"
  | "cancelled"
  | "on_hold"
  | "paused"
  | "expired"
  | "refunded"
  | "revoked";

/// Statuses that entitle the user. Mirrors sync_premium_until() in SQL —
/// if you change one, change the other.
export const ENTITLING: SubStatus[] = ["active", "in_grace", "cancelled"];

// ---------------------------------------------------------------------
//  OAuth: service-account JSON -> access token (RS256, via WebCrypto)
// ---------------------------------------------------------------------

let cachedToken: { token: string; expiresAt: number } | null = null;

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/// Mint (and cache) a Google OAuth access token for the Android
/// Publisher API. Tokens last an hour; we re-use until 5 min before.
export async function getPlayAccessToken(): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt) {
    return cachedToken.token;
  }

  const raw = Deno.env.get("GOOGLE_PLAY_SA_JSON");
  if (!raw) {
    throw new Error(
      "GOOGLE_PLAY_SA_JSON is not set — server-side purchase verification " +
        "cannot run. See supabase/functions/_shared/play.ts.",
    );
  }

  let sa: { client_email: string; private_key: string };
  try {
    sa = JSON.parse(raw);
  } catch {
    throw new Error("GOOGLE_PLAY_SA_JSON is not valid JSON.");
  }
  if (!sa.client_email || !sa.private_key) {
    throw new Error(
      "GOOGLE_PLAY_SA_JSON is missing client_email / private_key.",
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const unsigned = `${b64url(enc.encode(JSON.stringify(header)))}.${
    b64url(enc.encode(JSON.stringify(claims)))
  }`;

  // Secrets often arrive with literal "\n" instead of real newlines.
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(unsigned)),
  );
  const assertion = `${unsigned}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    throw new Error(
      `Google OAuth refused the service account: ${JSON.stringify(json)}`,
    );
  }

  cachedToken = {
    token: json.access_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000 - 300_000,
  };
  return cachedToken.token;
}

// ---------------------------------------------------------------------
//  Subscription lookup
// ---------------------------------------------------------------------

export interface PlaySubscription {
  status: SubStatus;
  productId: string | null;
  expiryTime: string | null;
  autoRenewing: boolean;
  orderId: string | null;
  isTestPurchase: boolean;
  raw: unknown;
}

/// Ask Play about a purchase token. Throws on a transport/auth failure
/// so the caller can tell "Google says no" apart from "we couldn't ask".
export async function getPlaySubscription(
  purchaseToken: string,
): Promise<PlaySubscription | null> {
  const token = await getPlayAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(PLAY_PACKAGE_NAME)}/purchases/subscriptionsv2/tokens/` +
    `${encodeURIComponent(purchaseToken)}`;

  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (res.status === 404 || res.status === 410) {
    // Play has never seen this token, or it is long gone. Either way it
    // entitles nobody — a forged token lands here.
    return null;
  }
  if (!res.ok) {
    throw new Error(
      `Play API ${res.status}: ${(await res.text()).slice(0, 400)}`,
    );
  }

  const body = await res.json();
  return mapPlaySubscription(body);
}

/// Translate Play's subscriptionState into our own vocabulary.
///
/// The important nuances, all of which cost money if they're wrong:
///   * CANCELED means auto-renew is OFF, not that access ended — the
///     user keeps what they already paid for until expiryTime.
///   * IN_GRACE_PERIOD means Google is still retrying their card, and
///     Google asks that access continue.
///   * ON_HOLD / PAUSED mean access stops but the subscription is not
///     dead, so the row stays and can come back to life.
export function mapPlaySubscription(body: any): PlaySubscription {
  const line = Array.isArray(body?.lineItems) && body.lineItems.length > 0
    ? body.lineItems[0]
    : null;

  const state = String(body?.subscriptionState ?? "");
  let status: SubStatus;
  switch (state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      status = "active";
      break;
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      status = "in_grace";
      break;
    case "SUBSCRIPTION_STATE_CANCELED":
      status = "cancelled";
      break;
    case "SUBSCRIPTION_STATE_ON_HOLD":
      status = "on_hold";
      break;
    case "SUBSCRIPTION_STATE_PAUSED":
      status = "paused";
      break;
    case "SUBSCRIPTION_STATE_EXPIRED":
      status = "expired";
      break;
    case "SUBSCRIPTION_STATE_PENDING":
    case "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED":
    case "SUBSCRIPTION_STATE_UNSPECIFIED":
    default:
      status = "pending";
      break;
  }

  return {
    status,
    productId: line?.productId ?? null,
    expiryTime: line?.expiryTime ?? null,
    autoRenewing: Boolean(line?.autoRenewingPlan?.autoRenewEnabled),
    orderId: body?.latestOrderId ?? null,
    isTestPurchase: Boolean(body?.testPurchase),
    raw: body,
  };
}
