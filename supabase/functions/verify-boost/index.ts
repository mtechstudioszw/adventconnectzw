// =====================================================================
//  Edge Function: verify-boost
//
//  Turns a paid one-time boost into a featured listing or job — and is
//  the ONLY thing that can (patch 289: grant_boost is revoked from
//  members; the table guards snap is_featured back on any client write).
//
//  The client sends the purchase token, the SKU and the target it meant
//  to boost. This function:
//    1. asks Google Play what the token really is (never the client);
//    2. takes the target from the tag Play recorded at purchase time
//       ("boost:p:<id>" / "boost:j:<id>"), falling back to the body only
//       if Play has none;
//    3. calls grant_boost() with the service role — which checks the
//       member owns the target and is idempotent on the token, so a
//       replayed purchase never stacks a second boost;
//    4. acknowledges the purchase server-side, so Play can't refund a
//       boost we delivered.
//  The app then CONSUMES the purchase so the same SKU can be bought
//  again.
//
//  verify_jwt MUST stay ON: the caller's identity is the whole point.
// =====================================================================
// @ts-nocheck
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  acknowledgePlayProductPurchase,
  getPlayProductPurchase,
} from "../_shared/play.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/// SKU → what it buys. Mirrors BoostCatalog in
/// lib/services/billing/boost_catalog.dart; the server's copy decides.
const SKUS: Record<string, { type: "product" | "job"; days: number }> = {
  listing_boost_7d: { type: "product", days: 7 },
  job_boost_14d: { type: "job", days: 14 },
};

/// Call-minute packs (patch 305, 3 Nov 2026). One-off, consumable;
/// granted to the CALLER (no target), valid 30 days, spent only after the
/// plan's own call allowance runs out. Mirrors CallPackCatalog in
/// lib/services/billing/call_pack_catalog.dart; the server's copy decides.
const PACKS: Record<string, { minutes: number; days: number }> = {
  call_minutes_300: { minutes: 300, days: 30 },
  call_minutes_1200: { minutes: 1200, days: 30 },
};

// Advent AI question packs (patch 309): questions the member keeps until
// used, spent after their free and Premium questions.
const AI_PACKS: Record<string, { units: number }> = {
  ai_questions_50: { units: 50 },
};

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

/// "boost:p:42" → { type: "product", id: 42 }.
function parseTag(tag: string | null | undefined) {
  const m = /^boost:([pj]):(\d{1,18})$/.exec(String(tag ?? ""));
  if (!m) return null;
  return { type: m[1] === "p" ? "product" : "job", id: Number(m[2]) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ ok: false, error: "unauthenticated" }, 401);
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  const user = userData?.user;
  if (userErr || !user) return json({ ok: false, error: "unauthenticated" }, 401);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  const platform = String(body?.platform ?? "google_play");
  const productId = String(body?.product_id ?? "");
  const purchaseToken = String(body?.purchase_token ?? "");
  const sku = SKUS[productId];
  const pack = PACKS[productId];
  const aiPack = AI_PACKS[productId];

  if (platform !== "google_play") {
    return json({ ok: false, error: "unsupported_platform" }, 400);
  }
  if (!sku && !pack && !aiPack) {
    return json({ ok: false, error: "unknown_product" }, 400);
  }
  if (!purchaseToken) return json({ ok: false, error: "missing_token" }, 400);

  let purchase;
  try {
    purchase = await getPlayProductPurchase(productId, purchaseToken);
  } catch (e) {
    console.error("Play lookup failed:", e);
    return json({ ok: false, error: "verification_unavailable" }, 503);
  }
  if (!purchase) return json({ ok: false, error: "invalid_purchase" }, 400);
  if (purchase.purchaseState === 2) {
    return json({ ok: false, error: "pending" }, 409);
  }
  if (purchase.purchaseState !== 0) {
    return json({ ok: false, error: "invalid_purchase" }, 400);
  }

  // ---- Advent AI question pack: credit the buyer --------------------
  if (aiPack) {
    const { data: left, error: aiErr } = await admin.rpc(
      "grant_ai_questions",
      {
        p_user: user.id,
        p_product: productId,
        p_units: aiPack.units,
        p_token: purchaseToken,
        p_order: purchase.orderId,
      },
    );
    if (aiErr) {
      // Not acknowledged, so Play refunds it within 3 days.
      console.error("grant_ai_questions failed:", aiErr);
      return json({ ok: false, error: "write_failed" }, 500);
    }
    try {
      await acknowledgePlayProductPurchase(productId, purchaseToken);
    } catch (e) {
      console.error("acknowledge failed:", e);
    }
    return json({
      ok: true,
      questions: aiPack.units,
      questions_left: left,
      test_purchase: purchase.isTestPurchase,
    });
  }

  // ---- call-minute pack: credit the caller, no target ---------------
  if (pack) {
    const { data: expiresAt, error: packErr } = await admin.rpc(
      "grant_call_minutes",
      {
        p_user: user.id,
        p_product: productId,
        p_minutes: pack.minutes,
        p_days: pack.days,
        p_token: purchaseToken,
        p_order: purchase.orderId,
      },
    );
    if (packErr) {
      // Not acknowledged, so Play refunds it within 3 days.
      console.error("grant_call_minutes failed:", packErr);
      return json({ ok: false, error: "write_failed" }, 500);
    }
    try {
      await acknowledgePlayProductPurchase(productId, purchaseToken);
    } catch (e) {
      console.error("acknowledge failed:", e);
    }
    return json({
      ok: true,
      minutes: pack.minutes,
      expires_at: expiresAt,
      test_purchase: purchase.isTestPurchase,
    });
  }

  const target = parseTag(purchase.accountTag) ??
    (body?.target_id != null
      ? { type: sku.type, id: Number(body.target_id) }
      : null);
  if (!target || target.type !== sku.type || !Number.isFinite(target.id)) {
    return json({ ok: false, error: "no_target" }, 400);
  }

  const { data: endsAt, error: grantErr } = await admin.rpc("grant_boost", {
    p_user: user.id,
    p_target_type: target.type,
    p_target_id: target.id,
    p_days: sku.days,
    p_source: "purchase",
    p_token: purchaseToken,
    p_order: purchase.orderId,
  });
  if (grantErr) {
    // BOOST_NOT_OWNER / BOOST_NOT_LIVE: the money is real but the target
    // can't take it. Not acknowledged, so Play refunds it within 3 days.
    console.error("grant_boost failed:", grantErr);
    const code = String(grantErr.message ?? "");
    return json({
      ok: false,
      error: code.includes("BOOST_NOT_OWNER")
        ? "not_owner"
        : code.includes("BOOST_NOT_LIVE")
        ? "not_live"
        : "write_failed",
    }, code.includes("BOOST_") ? 409 : 500);
  }

  try {
    await acknowledgePlayProductPurchase(productId, purchaseToken);
  } catch (e) {
    // The boost is granted; the app's consume also acknowledges. Logged
    // so a failure here is visible rather than a silent refund.
    console.error("acknowledge failed:", e);
  }

  return json({
    ok: true,
    target_type: target.type,
    target_id: target.id,
    ends_at: endsAt,
    test_purchase: purchase.isTestPurchase,
  });
});
