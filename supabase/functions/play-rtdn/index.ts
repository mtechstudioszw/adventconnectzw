// =====================================================================
//  Edge Function: play-rtdn
//
//  Google Play Real-time Developer Notifications, delivered by Pub/Sub
//  push. This is what makes a cancellation, a lapse or a REFUND reach
//  the app without polling — and it is the only reason "premium ends
//  when the money stops" is true rather than aspirational.
//
//  Design choice: a notification tells us only THAT something changed.
//  Rather than hand-mapping Google's thirteen notification types, we
//  re-ask the Play API what the subscription is now and write that.
//  One source of truth, and it cannot drift from verify-purchase.
//
//  SETUP (Play Console → Monetisation setup → Real-time developer
//  notifications):
//    1. Create a Pub/Sub topic in Google Cloud, e.g.
//         projects/<project>/topics/play-rtdn
//    2. Grant  google-play-developer-notifications@system.gserviceaccount.com
//       the "Pub/Sub Publisher" role on that topic.
//    3. Create a PUSH subscription pointing at this function's URL with
//       the shared secret appended:
//         https://<ref>.functions.supabase.co/play-rtdn?secret=<RTDN_SECRET>
//    4. supabase secrets set RTDN_SECRET=<a long random string>
//
//  verify_jwt MUST be OFF (Pub/Sub is anonymous) — the shared secret in
//  the query string is what authenticates the caller instead.
// =====================================================================
// @ts-nocheck
import { createClient } from "jsr:@supabase/supabase-js@2";
import { ENTITLING, getPlaySubscription } from "../_shared/play.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RTDN_SECRET = Deno.env.get("RTDN_SECRET") ?? "";

/// Google's notificationType -> a label for the audit log. The STATUS
/// still comes from re-reading the subscription; this is only so a
/// human reading subscription_events can see what Google announced.
const EVENT_NAMES: Record<number, string> = {
  1: "recovered",
  2: "renewed",
  3: "cancelled",
  4: "purchased",
  5: "hold",
  6: "grace",
  7: "restarted",
  8: "price_change_confirmed",
  9: "deferred",
  10: "paused",
  11: "pause_schedule_changed",
  12: "revoked",
  13: "expired",
  20: "pending_purchase_cancelled",
};

/// Constant-time string compare, so the shared secret can't be recovered
/// a character at a time by timing the response.
function secretMatches(supplied: string | null): boolean {
  if (supplied === null) return false;
  const a = new TextEncoder().encode(supplied);
  const b = new TextEncoder().encode(RTDN_SECRET);
  // Length is not secret-dependent enough to matter, but comparing
  // different lengths byte-wise would read out of bounds.
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  // Pub/Sub retries anything that isn't a 2xx, forever-ish. So every
  // path below that isn't "we might succeed on a retry" returns 200.
  const url = new URL(req.url);

  // ---- FAIL CLOSED --------------------------------------------------
  //
  // This check used to read `if (RTDN_SECRET && supplied !== RTDN_SECRET)`,
  // which skipped authentication ENTIRELY whenever the secret was unset —
  // and it is unset today, because Pub/Sub has not been configured yet.
  // `verify_jwt` is deliberately OFF for this function (Pub/Sub posts
  // anonymously), so the shared secret is the ONLY thing standing in
  // front of it. Together that made this a fully unauthenticated endpoint
  // holding the service-role key.
  //
  // The damaging path is the voided-purchase branch below: it does NOT
  // re-read anything from Google, it trusts `refundType` straight out of
  // the request body, flips the subscription to refunded/revoked and
  // calls sync_premium_until. So anyone who obtained a purchase_token
  // could strip premium from a paying subscriber, unauthenticated and at
  // will. Everything else here is at least anchored to a Play API read.
  //
  // An unconfigured secret must therefore mean "accept nothing", never
  // "accept everything". 503 (not 403) because this IS a state a retry
  // could recover from once the secret is set, and Pub/Sub retrying is
  // the behaviour we want then.
  if (RTDN_SECRET.length === 0) {
    console.error(
      "RTDN_SECRET is not set — refusing every notification. Run " +
        "`supabase secrets set RTDN_SECRET=<long random string>` and point " +
        "the Pub/Sub push subscription at ?secret=<same value>.",
    );
    return new Response("not configured", { status: 503 });
  }
  if (!secretMatches(url.searchParams.get("secret"))) {
    // Wrong caller. 403 and no retry.
    return new Response("forbidden", { status: 403 });
  }

  let envelope: any;
  try {
    envelope = await req.json();
  } catch {
    return new Response("bad body", { status: 200 });
  }

  const encoded = envelope?.message?.data;
  if (!encoded) return new Response("no data", { status: 200 });

  let payload: any;
  try {
    payload = JSON.parse(atob(encoded));
  } catch {
    return new Response("undecodable", { status: 200 });
  }

  // Play Console sends one of these when you press "Send test
  // notification". Acknowledge it so the setup screen goes green.
  if (payload.testNotification) {
    console.log("RTDN test notification received");
    return new Response("ok", { status: 200 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const voided = payload.voidedPurchaseNotification;
  const subNote = payload.subscriptionNotification;
  const purchaseToken = voided?.purchaseToken ?? subNote?.purchaseToken;
  if (!purchaseToken) return new Response("not a subscription", { status: 200 });

  const { data: existing } = await admin
    .from("subscriptions")
    .select("id, user_id, status")
    .eq("platform", "google_play")
    .eq("purchase_token", purchaseToken)
    .maybeSingle();

  if (!existing) {
    // A purchase we've never seen — usually a notification arriving
    // before the client finished verifying. verify-purchase will pick it
    // up; nothing to do, and retrying won't help.
    console.log("RTDN for an unknown token; ignoring");
    return new Response("unknown token", { status: 200 });
  }

  // ---- refund / chargeback: cut off immediately ----------------------
  if (voided) {
    // 1 = the order was refunded, 2 = it was charged back.
    const status = voided.refundType === 1 ? "refunded" : "revoked";
    await admin
      .from("subscriptions")
      .update({
        status,
        auto_renewing: false,
        last_verified_at: new Date().toISOString(),
        raw: payload,
      })
      .eq("id", existing.id);

    await admin.rpc("sync_premium_until", { p_user: existing.user_id });
    await admin.from("subscription_events").insert({
      subscription_id: existing.id,
      user_id: existing.user_id,
      platform: "google_play",
      event_type: status,
      from_status: existing.status,
      to_status: status,
      raw: payload,
    });
    return new Response("ok", { status: 200 });
  }

  // ---- everything else: re-read the truth from Play ------------------
  let sub;
  try {
    sub = await getPlaySubscription(purchaseToken);
  } catch (e) {
    console.error("RTDN Play lookup failed:", e);
    // OUR failure — let Pub/Sub retry this one.
    return new Response("upstream unavailable", { status: 503 });
  }

  if (!sub) {
    await admin
      .from("subscriptions")
      .update({ status: "expired", auto_renewing: false })
      .eq("id", existing.id);
    await admin.rpc("sync_premium_until", { p_user: existing.user_id });
    return new Response("ok", { status: 200 });
  }

  await admin
    .from("subscriptions")
    .update({
      status: sub.status,
      current_period_end: sub.expiryTime,
      auto_renewing: sub.autoRenewing,
      last_verified_at: new Date().toISOString(),
      raw: sub.raw,
    })
    .eq("id", existing.id);

  await admin.rpc("sync_premium_until", { p_user: existing.user_id });

  const notificationType = Number(subNote?.notificationType ?? 0);
  await admin.from("subscription_events").insert({
    subscription_id: existing.id,
    user_id: existing.user_id,
    platform: "google_play",
    event_type: EVENT_NAMES[notificationType] ?? "renewed",
    from_status: existing.status,
    to_status: sub.status,
    raw: payload,
  });

  // A renewal deserves a receipt; a mere state change does not.
  const wasEntitled = ENTITLING.includes(existing.status);
  if (notificationType === 2 && wasEntitled && ENTITLING.includes(sub.status)) {
    const when = sub.expiryTime
      ? new Date(sub.expiryTime).toLocaleDateString("en-GB", {
        day: "numeric",
        month: "long",
        year: "numeric",
      })
      : null;
    await admin.from("notifications").insert({
      user_id: existing.user_id,
      title: "Subscription renewed",
      body: when
        ? `Your Adventist Super App Premium renewed. Ads stay off until ${when}. ` +
          `Google Play has emailed you the payment receipt.`
        : `Your Adventist Super App Premium renewed. ` +
          `Google Play has emailed you the payment receipt.`,
      type: "payment_receipt",
      reference_type: "subscription",
      reference_id: existing.id,
    });
  }

  return new Response("ok", { status: 200 });
});
