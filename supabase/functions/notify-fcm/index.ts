// =====================================================================
//  Edge Function: notify-fcm
//
//  Trigger:  Supabase Database Webhook on public.notifications INSERT
//  Purpose:  When the DB writes a row to notifications, look up the
//            recipient's profiles.fcm_token and push a FCM v1 message.
//
//  Env vars (configure as Supabase Edge Function secrets):
//    FCM_SERVICE_ACCOUNT_JSON  — paste of the Firebase service account
//                                 JSON. Do not commit. Set via dashboard.
//    SUPABASE_URL              — auto-injected by Supabase.
//    SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase.
//
//  Deploy:
//    supabase functions deploy notify-fcm
//
//  This file runs on Deno (Supabase Edge Functions), not Node.js. The
//  @ts-nocheck pragma silences VS Code's Node-flavoured TypeScript
//  checker (it doesn't know about `Deno.*` globals or URL imports).
//  The file is still fully type-checked when deployed.
// =====================================================================

// @ts-nocheck

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// Minimal shape we read out of the service-account JSON.
interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

// Webhook payload Supabase ships on a row INSERT.
interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: Record<string, unknown>;
  old_record: Record<string, unknown> | null;
}

// ---------- helpers ---------------------------------------------------

function base64UrlEncode(input: string | Uint8Array): string {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;
  let str = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    str += String.fromCharCode(bytes[i]);
  }
  return btoa(str).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  // Strip the BEGIN/END markers and any whitespace/newlines, then
  // base64-decode the body into raw key bytes.
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out.buffer;
}

async function signJwtRs256(
  payload: Record<string, unknown>,
  account: ServiceAccount,
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function fetchGoogleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const jwt = await signJwtRs256(
    {
      iss: account.client_email,
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    account,
  );

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Google token exchange failed (${resp.status}): ${text}`);
  }
  const json = (await resp.json()) as { access_token?: string };
  if (!json.access_token) {
    throw new Error("Google token exchange returned no access_token");
  }
  return json.access_token;
}

async function sendFcm({
  account,
  accessToken,
  deviceToken,
  title,
  body,
  data,
}: {
  account: ServiceAccount;
  accessToken: string;
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, string>;
}): Promise<void> {
  const url =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  const message = {
    message: {
      token: deviceToken,
      notification: { title, body },
      data, // all values must be strings per FCM v1
      android: {
        priority: "HIGH",
        notification: { channel_id: "advent_connect_zw_default" },
      },
    },
  };
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(message),
  });
  if (!resp.ok) {
    const text = await resp.text();
    // Bubble up so the webhook surface sees the failure in Supabase logs.
    throw new Error(`FCM send failed (${resp.status}): ${text}`);
  }
}

// ---------- handler --------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let payload: WebhookPayload;
  try {
    payload = (await req.json()) as WebhookPayload;
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  // Only fire on a fresh notification row.
  if (payload.type !== "INSERT" || payload.table !== "notifications") {
    return new Response("Ignored", { status: 200 });
  }

  const row = payload.record;
  const userId = row.user_id as string | undefined;
  const title = (row.title as string | undefined) ?? "Advent Connect ZW";
  const body = (row.body as string | undefined) ?? "";
  const referenceId = (row.reference_id as string | null) ?? "";
  const referenceType = (row.reference_type as string | null) ?? "";
  const notifType = (row.type as string | null) ?? "general";

  if (!userId) {
    return new Response("Missing user_id", { status: 400 });
  }

  // Look up the device token. service_role bypasses RLS so we can read
  // anyone's row (the webhook authenticates this call, not the user).
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: profile, error } = await supabase
    .from("profiles")
    .select("fcm_token")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    return new Response(`Profile lookup failed: ${error.message}`, {
      status: 500,
    });
  }
  const deviceToken = profile?.fcm_token as string | null | undefined;
  if (!deviceToken) {
    // Not an error — user just hasn't installed the app or signed in
    // anywhere yet. The in-app inbox still shows the notification.
    return new Response("No device token; skipped", { status: 200 });
  }

  let account: ServiceAccount;
  try {
    const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
    if (!raw) throw new Error("FCM_SERVICE_ACCOUNT_JSON not set");
    account = JSON.parse(raw) as ServiceAccount;
    if (!account.client_email || !account.private_key || !account.project_id) {
      throw new Error("FCM_SERVICE_ACCOUNT_JSON missing required fields");
    }
  } catch (e) {
    return new Response(
      `FCM service account misconfigured: ${(e as Error).message}`,
      { status: 500 },
    );
  }

  try {
    const accessToken = await fetchGoogleAccessToken(account);
    await sendFcm({
      account,
      accessToken,
      deviceToken,
      title,
      body,
      data: {
        reference_id: referenceId,
        reference_type: referenceType,
        type: notifType,
      },
    });
  } catch (e) {
    return new Response(`Push failed: ${(e as Error).message}`, {
      status: 500,
    });
  }

  return new Response("ok", { status: 200 });
});
