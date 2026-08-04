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
//    FCM_HOOK_SECRET           — shared secret proving the caller is our
//                                 own database webhook. See below.
//    SUPABASE_URL              — auto-injected by Supabase.
//    SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase.
//
//  ## Why FCM_HOOK_SECRET exists (added 4 Aug 2026)
//
//  This function ran with `verify_jwt = false` and NO authentication of
//  any kind. It reads `title`, `body` and `user_id` straight out of the
//  request body, then uses the SERVICE-ROLE key to look up that user's
//  device token and push to it.
//
//  So anyone who knew the URL could send any notification, with any
//  wording, to any member — delivered through the app's own channel with
//  the app's own icon. "Your account is suspended, tap to verify" is
//  indistinguishable from a real notification. Member IDs are visible to
//  any signed-in user via posts and profiles, so targeting was trivial.
//
//  The old comment claimed "the webhook authenticates this call". It did
//  not. The webhook sent `Authorization: Bearer <ANON KEY>` — and the anon
//  key is public by design; it ships inside the APK. Checking it would
//  have been theatre, since every attacker already has it.
//
//  So the trigger now also sends `x-fcm-secret`, and this function
//  requires it. FAIL CLOSED: a missing or wrong secret is rejected, and a
//  missing ENV VAR is rejected too. "Authenticate only if someone
//  remembered to configure a secret" is the idiom that left play-rtdn
//  wide open; it is not repeated here.
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
  dataOnly = false,
  imageUrl,
}: {
  account: ServiceAccount;
  accessToken: string;
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, string>;
  // When true, send a DATA-ONLY message (no `notification` block). The app
  // then renders the notification itself with an inline Reply button + the
  // sender's photo (chat messages). When false, the system renders it.
  dataOnly?: boolean;
  // Big-picture art. A "🔴 X is live" banner with the broadcast's own frame
  // is the difference between a line of text and something you tap — it is
  // what YouTube's own notifications do.
  imageUrl?: string | null;
}): Promise<void> {
  const url =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  // For data-only, fold title/body into data so the app can build the banner.
  const fullData = dataOnly ? { ...data, title, body } : data;
  // deno-lint-ignore no-explicit-any
  const message: any = {
    message: {
      token: deviceToken,
      data: fullData, // all values must be strings per FCM v1
      android: {
        priority: "HIGH",
      },
    },
  };
  if (!dataOnly) {
    message.message.notification = { title, body };
    message.message.android.notification = {
      channel_id: "advent_connect_zw_default",
    };
    if (imageUrl) {
      // `notification.image` covers Android big-picture; iOS needs the
      // same URL echoed through APNs' fcm_options for its attachment.
      message.message.notification.image = imageUrl;
      message.message.android.notification.image = imageUrl;
      message.message.apns = {
        payload: { aps: { "mutable-content": 1 } },
        fcm_options: { image: imageUrl },
      };
    }
  }
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

// Map a `notifications.type` value to one of the five category keys
// stored in `profiles.notif_categories`. Returns null when the type
// doesn't map (we fall through and send by default in that case).
function mapTypeToCategory(type: string): string | null {
  const t = (type || "").toLowerCase();
  // Likes & comments on posts/comments — the Settings "Likes & comments"
  // toggle (profiles.notif_categories.social). Checked before the generic
  // rules so e.g. "post_comment" isn't mis-bucketed.
  if (
    t === "post_like" ||
    t === "post_comment" ||
    t === "comment_reply" ||
    t === "comment_like" ||
    t === "reaction"
  ) {
    return "social";
  }
  if (t.includes("event")) return "events";
  if (t.includes("prayer")) return "prayers";
  if (t.includes("message") || t === "chat") return "messages";
  // News + daily devotion share the "news" toggle (the Settings screen's
  // content toggle). Without this the News switch was decorative — news
  // pushes always sent regardless of the user's choice.
  if (t.includes("news") || t.includes("devotion")) return "news";
  if (
    t.includes("market") ||
    t.includes("product") ||
    t.includes("seller") ||
    t.includes("job")
  ) {
    return "marketplace";
  }
  if (
    t.includes("announce") ||
    t.includes("urgent") ||
    t.includes("church_admin")
  ) {
    return "announcements";
  }
  return null;
}

// ---------- handler --------------------------------------------------

/// Constant-time compare so the secret can't be recovered a byte at a
/// time by timing the response.
function secretOk(supplied: string | null): boolean {
  const expected = Deno.env.get("FCM_HOOK_SECRET") ?? "";
  // No configured secret means we cannot authenticate anyone. Reject.
  if (expected.length === 0 || supplied === null) return false;
  const a = new TextEncoder().encode(supplied);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Only our own database webhook may ask this function to push. 401 with
  // no detail — an attacker probing it learns nothing about whether the
  // secret is unset, wrong, or the right length.
  if (!secretOk(req.headers.get("x-fcm-secret"))) {
    console.error("notify-fcm: rejected a call with a missing/invalid secret");
    return new Response("Unauthorized", { status: 401 });
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
    .select("fcm_token, notif_categories")
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

  // Honour per-category opt-outs from Settings. Map the notification
  // row's `type` to a category key matching profiles.notif_categories
  // (events / prayers / messages / marketplace / announcements).
  // Anything that doesn't map cleanly falls through as "on" so we
  // don't silently swallow new notification types.
  const category = mapTypeToCategory(notifType);
  const prefs = (profile?.notif_categories ?? {}) as Record<string, unknown>;
  if (category && prefs[category] === false) {
    return new Response(`Skipped: ${category} muted`, { status: 200 });
  }

  // Honour per-conversation mute (patch_058). Message notifications carry
  // reference_type 'conversation' + reference_id = the conversation id; if
  // the recipient muted that thread, suppress the push (the in-app inbox
  // still updates).
  if (referenceType === "conversation" && referenceId) {
    const convId = Number(referenceId);
    if (!Number.isNaN(convId)) {
      const { data: cs } = await supabase
        .from("conversation_state")
        .select("muted")
        .eq("user_id", userId)
        .eq("conversation_id", convId)
        .maybeSingle();
      if (cs?.muted === true) {
        return new Response("Skipped: conversation muted", { status: 200 });
      }
    }
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

  // For chat pushes, look up the latest sender's photo so the app can show it
  // as the notification's large icon, and send DATA-ONLY so the app renders
  // the banner itself with an inline Reply button (#10/#11). Non-chat pushes
  // stay system-rendered.
  const isConversation = referenceType === "conversation" && !!referenceId;
  let senderPhoto = "";
  if (isConversation) {
    try {
      const { data: lastMsg } = await supabase
        .from("messages")
        .select("sender_id")
        .eq("conversation_id", Number(referenceId))
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (lastMsg?.sender_id) {
        const { data: sp } = await supabase
          .from("profiles")
          .select("profile_photo_url")
          .eq("id", lastMsg.sender_id)
          .maybeSingle();
        senderPhoto = (sp?.profile_photo_url as string | null) ?? "";
      }
    } catch (_) {
      // best-effort; the notification just shows without a photo.
    }
  }

  // Video notifications carry the broadcast's own frame, the way YouTube's
  // do. reference_type 'video' + reference_id = the YouTube video id, which
  // is exactly what youtube_fanout_notification writes (patch_156).
  let imageUrl: string | null = null;
  if (referenceType === "video" && referenceId) {
    try {
      const { data: vid } = await supabase
        .from("youtube_videos")
        .select("thumbnail_url")
        .eq("video_id", referenceId)
        .maybeSingle();
      imageUrl = (vid?.thumbnail_url as string | null) ?? null;
    } catch (_) {
      // best-effort; the fallback below still applies.
    }
    // Belt and braces (3 Aug 2026). The row lookup can miss for reasons
    // that have nothing to do with the push being wrong: a live
    // broadcast notified in the same instant the row is written, or a
    // video deleted afterwards (20 historical notifications are orphaned
    // exactly that way). YouTube's thumbnail URL is deterministic from
    // the video id, so there is never a good reason to send a live
    // broadcast out as a bare text banner.
    if (!imageUrl) {
      imageUrl = `https://i.ytimg.com/vi/${referenceId}/hqdefault.jpg`;
    }
  }

  try {
    const accessToken = await fetchGoogleAccessToken(account);
    await sendFcm({
      account,
      accessToken,
      deviceToken,
      imageUrl,
      title,
      body,
      dataOnly: isConversation,
      data: {
        reference_id: referenceId,
        reference_type: referenceType,
        type: notifType,
        ...(isConversation ? { sender_photo: senderPhoto } : {}),
      },
    });
  } catch (e) {
    return new Response(`Push failed: ${(e as Error).message}`, {
      status: 500,
    });
  }

  // NOTE: we deliberately do NOT mark messages delivered here. Dispatching
  // a push does not mean the device received it (FCM queues for offline
  // devices), so marking delivered on dispatch produced a false ✓✓ when
  // the recipient's data was off. Delivery is marked by the recipient's
  // app when it actually receives/streams the message.

  return new Response("ok", { status: 200 });
});
