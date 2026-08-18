// =====================================================================
//  Edge Function: verify-purchase
//
//  The ONLY thing in the system allowed to turn money into premium.
//
//  The client sends a purchase token. This function asks the STORE what
//  that token really is, writes the result with the service role, and
//  recomputes profiles.premium_until from verified rows. The client is
//  never trusted, never believed, and cannot write premium itself — the
//  column is revoked from `authenticated` and a trigger snaps it back.
//
//  Founder decisions encoded here (3 Aug 2026):
//    * Premium is per ADVENT account. A purchase token is claimed by the
//      FIRST account that redeems it and can never be moved.
//    * Paying is the only route. No role — church admin, verified admin,
//      super admin — grants premium.
//    * A successful payment sends the user a receipt.
//
//  verify_jwt MUST stay ON: the caller's identity is the whole point.
// =====================================================================
// @ts-nocheck
import { createClient } from "jsr:@supabase/supabase-js@2";
import { ENTITLING, getPlaySubscription } from "../_shared/play.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/// A currency-agnostic receipt line. We never invent a price: whatever
/// the store charged is what the store's own receipt says, so ours
/// describes the subscription and the dates instead of guessing an
/// amount we may have wrong in the user's currency.
function receiptBody(expiry: string | null, isRenewal: boolean): string {
  const when = expiry
    ? new Date(expiry).toLocaleDateString("en-GB", {
      day: "numeric",
      month: "long",
      year: "numeric",
    })
    : null;
  const head = isRenewal
    ? "Your Adventist Super App Premium subscription renewed."
    : "Thank you — your Adventist Super App Premium subscription is active.";
  return when
    ? `${head} Ads are off, and it renews on ${when}. ` +
      `Google Play has emailed you the payment receipt.`
    : `${head} Google Play has emailed you the payment receipt.`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // ---- who is asking -------------------------------------------------
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ ok: false, error: "unauthenticated" }, 401);

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  const user = userData?.user;
  if (userErr || !user) {
    return json({ ok: false, error: "unauthenticated" }, 401);
  }

  // ---- what are they claiming ----------------------------------------
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  const platform = String(body?.platform ?? "google_play");
  const purchaseToken = String(body?.purchase_token ?? "");
  const claimedProduct = body?.product_id ? String(body.product_id) : null;

  if (!purchaseToken) return json({ ok: false, error: "missing_token" }, 400);
  if (platform !== "google_play") {
    // iOS is deliberately not built yet. Say so honestly rather than
    // failing in a way that looks like a bug.
    return json({ ok: false, error: "unsupported_platform" }, 400);
  }

  // ---- ask the store, not the client ---------------------------------
  let sub;
  try {
    sub = await getPlaySubscription(purchaseToken);
  } catch (e) {
    console.error("Play lookup failed:", e);
    await admin.from("subscription_events").insert({
      user_id: user.id,
      platform,
      event_type: "verify_failed",
      raw: { message: String(e) },
    });
    // A transport/auth failure is OUR problem, not a rejection. 503 so
    // the client knows a retry is worth it.
    return json({ ok: false, error: "verification_unavailable" }, 503);
  }

  if (!sub) {
    // Play has never heard of this token. This is where a forged or
    // replayed token lands.
    await admin.from("subscription_events").insert({
      user_id: user.id,
      platform,
      event_type: "verify_failed",
      raw: { reason: "unknown_token" },
    });
    return json({ ok: false, error: "invalid_purchase" }, 400);
  }

  // ---- first claimer wins --------------------------------------------
  const { data: existing } = await admin
    .from("subscriptions")
    .select("id, user_id, status")
    .eq("platform", platform)
    .eq("purchase_token", purchaseToken)
    .maybeSingle();

  if (existing && existing.user_id !== user.id) {
    // Someone is trying to redeem a purchase that already belongs to
    // another Advent account. The DB would refuse this anyway (unique
    // token + an immutable-owner trigger); answering clearly here means
    // the user gets a sentence instead of a 500.
    await admin.from("subscription_events").insert({
      subscription_id: existing.id,
      user_id: user.id,
      platform,
      event_type: "verify_failed",
      raw: { reason: "already_claimed" },
    });
    return json({ ok: false, error: "already_claimed" }, 409);
  }

  const productId = sub.productId ?? claimedProduct ?? "premium_monthly";
  const row = {
    user_id: user.id,
    platform,
    product_id: productId,
    purchase_token: purchaseToken,
    status: sub.status,
    current_period_end: sub.expiryTime,
    auto_renewing: sub.autoRenewing,
    last_verified_at: new Date().toISOString(),
    raw: sub.raw,
  };

  let subscriptionId = existing?.id ?? null;
  if (existing) {
    const { error } = await admin
      .from("subscriptions")
      .update(row)
      .eq("id", existing.id);
    if (error) {
      console.error("subscription update failed:", error);
      return json({ ok: false, error: "write_failed" }, 500);
    }
  } else {
    const { data: inserted, error } = await admin
      .from("subscriptions")
      .insert(row)
      .select("id")
      .single();
    if (error) {
      console.error("subscription insert failed:", error);
      return json({ ok: false, error: "write_failed" }, 500);
    }
    subscriptionId = inserted.id;
  }

  // ---- recompute premium from verified rows only ---------------------
  const { data: premiumUntil, error: syncErr } = await admin.rpc(
    "sync_premium_until",
    { p_user: user.id },
  );
  if (syncErr) {
    console.error("sync_premium_until failed:", syncErr);
    return json({ ok: false, error: "write_failed" }, 500);
  }

  const entitled = ENTITLING.includes(sub.status);
  const isRenewal = Boolean(existing) &&
    ENTITLING.includes(existing?.status ?? "");

  await admin.from("subscription_events").insert({
    subscription_id: subscriptionId,
    user_id: user.id,
    platform,
    event_type: existing ? (isRenewal ? "renewed" : "restored") : "purchased",
    from_status: existing?.status ?? null,
    to_status: sub.status,
    raw: { order_id: sub.orderId, test: sub.isTestPurchase },
  });

  // ---- the receipt ----------------------------------------------------
  // Only on a NEW entitlement, never on every re-verification — the app
  // re-verifies on resume, and a receipt every time the user opens the
  // app would be worse than none at all.
  if (entitled && !existing) {
    // notifications has no client INSERT policy by design; the service
    // role writes it, and the existing DB trigger fans it out to push.
    const { error: notifyErr } = await admin.from("notifications").insert({
      user_id: user.id,
      title: "Payment received",
      body: receiptBody(sub.expiryTime, false),
      type: "payment_receipt",
      reference_type: "subscription",
      reference_id: subscriptionId,
    });
    if (notifyErr) console.error("receipt notification failed:", notifyErr);
  }

  return json({
    ok: true,
    status: sub.status,
    entitled,
    premium_until: premiumUntil ?? null,
    test_purchase: sub.isTestPurchase,
  });
});
