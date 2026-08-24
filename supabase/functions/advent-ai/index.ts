// =====================================================================
//  Edge Function: advent-ai
//
//  The only way a message reaches the AI provider. Everything that
//  authorises, bounds or bills a request happens here or in Postgres —
//  never on the phone.
//
//  verify_jwt MUST stay ON. The caller's identity comes from the
//  verified token and from nowhere else: no user id is read from the
//  body, deliberately, so that a caller cannot name someone else.
//
//  ## Order of operations, and why it is this order
//
//   1. authenticate            — who is asking (JWT only)
//   2. validate input          — length, emptiness, shape
//   3. cheap jailbreak filter  — before we pay for anything
//   4. rate limit              — before we pay for anything
//   5. DEBIT a unit            — ai_spend_unit; NULL means refuse
//   6. call the provider       — streaming
//   7. persist + settle cost   — actual provider usage
//   8. refund on ANY failure   — a member never pays for silence
//
//  The debit is deliberately BEFORE the provider call. Debiting after
//  would mean a crash, a timeout or a disconnect mid-stream produced a
//  free request, which is the hole a script would find first. Paying it
//  back on failure is cheap; letting it be skipped is not.
//
//  ## Cost accounting — read before changing step 5 or 7
//
//  ai_spend_unit records cost into ai_spend_daily, and the global
//  ceilings read that table. But the real cost is unknown until the
//  provider reports usage, AFTER the call. Debiting with 0 would leave
//  free_cost_micros permanently zero and the ceiling protecting the
//  founder's card would never trip — the guard would look present and
//  do nothing.
//
//  So the debit carries a deliberately PESSIMISTIC estimate (the maximum
//  this request could possibly cost, given the context and output caps),
//  and step 7 settles it down to what was actually billed. Over-counting
//  briefly is safe: the worst case is the ceiling trips slightly early.
//  Under-counting is not.
//
//  Deploy:  supabase functions deploy advent-ai
//  Secrets: GEMINI_API_KEY   (server-side only — never in the app)
//           SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are auto-injected.
// =====================================================================
// @ts-nocheck
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  SYSTEM_PROMPT,
  JAILBREAK_REPLY,
  looksLikeJailbreak,
  wrapRetrieved,
} from "./prompt.ts";
import {
  AiProviderError,
  costMicros,
  getProvider,
} from "./provider.ts";
import { groundAppHelp, groundScripture } from "./bible.ts";

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

/// Error codes the app maps to copy. Deliberately a small closed set:
/// the app must never render a provider message, a Postgres error or a
/// stack trace, and it cannot render what it is never sent.
type ErrCode =
  | "unauthenticated"
  | "bad_request"
  | "too_long"
  | "rate_limited"
  | "out_of_credit"
  | "free_pool_closed"
  | "blocked"
  | "service_suspended"
  | "provider_failed";

function fail(code: ErrCode, status: number): Response {
  return json({ ok: false, error: code }, status);
}

/// Read several int config keys in one round trip.
async function loadConfig(
  admin: ReturnType<typeof createClient>,
  keys: string[],
): Promise<Record<string, string>> {
  const { data } = await admin
    .from("app_config")
    .select("key, value")
    .in("key", keys);
  const out: Record<string, string> = {};
  for (const row of data ?? []) out[row.key] = row.value;
  return out;
}

const int = (v: string | undefined, dflt: number): number => {
  const n = Number.parseInt(v ?? "", 10);
  return Number.isFinite(n) ? n : dflt;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return fail("bad_request", 405);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // ---- 1. who is asking ---------------------------------------------
  const jwt = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "");
  if (!jwt) return fail("unauthenticated", 401);

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  const user = userData?.user;
  if (userErr || !user) return fail("unauthenticated", 401);

  // ---- 2. validate ---------------------------------------------------
  let body: { conversation_id?: string; message?: string };
  try {
    body = await req.json();
  } catch {
    return fail("bad_request", 400);
  }

  const message = (body.message ?? "").trim();
  const conversationId = body.conversation_id;
  if (!message || !conversationId) return fail("bad_request", 400);

  const cfg = await loadConfig(admin, [
    "ai_service_state",
    "ai_provider",
    "ai_model",
    "ai_model_premium",
    "ai_max_request_chars",
    "ai_max_output_tokens",
    "ai_max_context_messages",
    "ai_rate_free_per_min",
    "ai_rate_free_per_day",
    "ai_rate_premium_per_min",
    "ai_rate_premium_per_day",
    "ai_price_in_micros_per_mtok",
    "ai_price_out_micros_per_mtok",
    "ai_price_in_micros_per_mtok_premium",
    "ai_price_out_micros_per_mtok_premium",
    "ai_max_context_tokens",
  ]);

  if ((cfg.ai_service_state ?? "live") !== "live") {
    return fail("service_suspended", 503);
  }

  const maxChars = int(cfg.ai_max_request_chars, 2000);
  if (message.length > maxChars) return fail("too_long", 413);

  // The conversation must belong to the caller. Checked explicitly
  // rather than relying on RLS, because this client is service_role and
  // RLS does not apply to it — the one place where "the database will
  // catch it" is false.
  const { data: convo } = await admin
    .from("ai_conversations")
    .select("id, user_id, title")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo || convo.user_id !== user.id) return fail("bad_request", 400);

  // ---- 3. cheap jailbreak filter -------------------------------------
  // Answered without touching the provider, and without spending a unit:
  // charging somebody for a canned refusal would be indefensible, and
  // paying a provider for it would be silly.
  if (looksLikeJailbreak(message)) {
    await admin.from("ai_messages").insert([
      { conversation_id: conversationId, role: "user", content: message,
        status: "complete", user_id: user.id },
      { conversation_id: conversationId, role: "assistant",
        content: JAILBREAK_REPLY, status: "complete", user_id: user.id },
    ]);
    return json({ ok: true, content: JAILBREAK_REPLY, refused: true });
  }

  // ---- 4. rate limit --------------------------------------------------
  // Enforced here because the config keys exist but no SQL function does.
  // Counts the member's OWN recent turns; a burst from one account cannot
  // be hidden by spreading it across conversations.
  const { data: isPrem } = await admin
    .rpc("ai_is_premium", { p_user: user.id });
  const premium = isPrem === true;

  const perMin = premium
    ? int(cfg.ai_rate_premium_per_min, 10)
    : int(cfg.ai_rate_free_per_min, 5);
  const perDay = premium
    ? int(cfg.ai_rate_premium_per_day, 200)
    : int(cfg.ai_rate_free_per_day, 10);

  const nowMs = Date.now();
  const minuteAgo = new Date(nowMs - 60_000).toISOString();
  const dayAgo = new Date(nowMs - 86_400_000).toISOString();

  const [{ count: lastMin }, { count: lastDay }] = await Promise.all([
    admin.from("ai_messages").select("id", { count: "exact", head: true })
      .eq("user_id", user.id).eq("role", "user").gte("created_at", minuteAgo),
    admin.from("ai_messages").select("id", { count: "exact", head: true })
      .eq("user_id", user.id).eq("role", "user").gte("created_at", dayAgo),
  ]);

  if ((lastMin ?? 0) >= perMin || (lastDay ?? 0) >= perDay) {
    return fail("rate_limited", 429);
  }

  // ---- 5. DEBIT -------------------------------------------------------
  // The authorisation point for the whole feature. NULL means refuse,
  // and nothing the client believes about its own balance is consulted.
  //
  // The estimate is the worst this request could cost: the full context
  // window in, the full output cap out. Settled to actual at step 7.
  // Prices are PER TIER, because the tiers answer on different models
  // and those models cost very different amounts. Billing a subscriber
  // at the free tier's rate would under-record real spend — the ledger
  // would drift below the invoice, which is the direction that hurts.
  const priceIn = premium
    ? int(cfg.ai_price_in_micros_per_mtok_premium, 750_000)
    : int(cfg.ai_price_in_micros_per_mtok, 250_000);
  const priceOut = premium
    ? int(cfg.ai_price_out_micros_per_mtok_premium, 3_750_000)
    : int(cfg.ai_price_out_micros_per_mtok, 1_500_000);
  const maxOut = int(cfg.ai_max_output_tokens, 1200);
  const maxCtx = int(cfg.ai_max_context_tokens, 8000);
  const estimate = Math.ceil(
    (maxCtx / 1_000_000) * priceIn + (maxOut / 1_000_000) * priceOut,
  );

  // Create the member's AI account if this is their first question.
  //
  // Without this, ai_spend_unit finds no ai_accounts row, returns NULL,
  // and EVERY new member is told they are out of credit on their very
  // first question — the feature is unusable for anyone who has not
  // somehow been given a row already.
  //
  // It belongs here rather than in the app or a signup trigger: here it
  // is guaranteed to have run before the first debit, it costs one call
  // on one request per member ever (the PK makes it a no-op afterwards),
  // and CLAUDE.md's standing rule is that touching the shared signup
  // trigger is how three production bugs happened in one day.
  await admin.rpc("ai_account_ensure", { p_user: user.id });

  const { data: pool } = await admin.rpc("ai_spend_unit", {
    p_user: user.id,
    p_cost_micros: estimate,
    p_conversation_id: conversationId,
  });

  if (!pool) {
    // Ask the balance function WHY, so the app can show the right
    // screen. Re-read rather than guessed: "out of credit" and "the
    // free pool is shut" are different sentences to a member.
    const { data: bal } = await admin
      .rpc("ai_my_balance_for", { p_user: user.id })
      .maybeSingle()
      .then((r) => r, () => ({ data: null }));
    const reason = bal?.reason ?? "out_of_credit";
    const code: ErrCode =
      reason === "free_pool_closed" ? "free_pool_closed"
        : reason === "blocked" ? "blocked"
        : reason === "service_suspended" ? "service_suspended"
        : "out_of_credit";
    return fail(code, 402);
  }

  // From here on the member has PAID for this exchange. Every exit path
  // below must either deliver an answer or refund.
  const refund = async (note: string) => {
    await admin.rpc("ai_refund_unit", {
      p_user: user.id,
      p_pool: pool,
      p_conversation_id: conversationId,
      p_note: note,
    });
  };

  // ---- 6. build the prompt --------------------------------------------
  // Recent turns only, oldest first, capped. Sending the whole history
  // would grow the bill with the conversation and eventually exceed the
  // window; the cap is what makes cost per message roughly flat.
  const maxTurns = int(cfg.ai_max_context_messages, 12);
  const { data: history } = await admin
    .from("ai_messages")
    .select("role, content")
    .eq("conversation_id", conversationId)
    .eq("status", "complete")
    .order("created_at", { ascending: false })
    .limit(maxTurns);

  const turns = (history ?? [])
    .reverse()
    .map((m) => ({ role: m.role, content: m.content }));

  // Gemini requires the conversation to BEGIN with a user turn.
  //
  // Taking the most recent N messages and reversing them can leave an
  // assistant reply at the front — trivially so whenever
  // ai_max_context_messages is odd, since the transcript alternates in
  // user/assistant pairs. The window would then open on half an
  // exchange and the request would be rejected, which is a config value
  // away at all times and would look like a provider outage.
  while (turns.length && turns[0].role !== "user") {
    turns.shift();
  }

  // ---- grounding ------------------------------------------------------
  // Real scripture, fetched from bible_verses (patches 241-251), so the
  // model quotes the text rather than its memory of it. Wrapped as data
  // so it can never read as instruction.
  //
  // Kept out of SYSTEM_PROMPT deliberately: that string is a constant
  // and stays cacheable across every request, while this changes per
  // question.
  //
  // Both lookups run together — they are independent, and doing them
  // in series would add a round trip to every question.
  const [scripture, appHelp] = await Promise.all([
    groundScripture(admin, message),
    groundAppHelp(admin, message),
  ]);

  const grounding: string[] = [];
  if (scripture) grounding.push(wrapRetrieved("VERSE TEXT", scripture));
  if (appHelp) grounding.push(wrapRetrieved("APP KNOWLEDGE", appHelp));

  // Grounding rides INSIDE the member's own turn, not as a separate one.
  //
  // A separate user turn would put two consecutive user roles in the
  // contents array, which Gemini treats as malformed. It is still
  // fenced by wrapRetrieved's delimiters and still labelled untrusted
  // data, so the injection boundary is unchanged — what changes is only
  // that the model sees one well-formed turn instead of two.
  //
  // The question goes LAST so it is the final thing read, after its
  // supporting material rather than buried above it.
  const finalTurn = grounding.length
    ? `${grounding.join("\n\n")}\n\n${message}`
    : message;

  turns.push({ role: "user", content: finalTurn });

  // ---- 7. stream ------------------------------------------------------
  const provider = getProvider(cfg.ai_provider ?? "gemini");
  // Defaults are the CURRENT model ids. gemini-2.5-* was retired to new
  // API keys mid-build ("no longer available to new users"), so a stale
  // fallback here is not a slightly-older model, it is a 404 on every
  // request. Keep these in step with app_config.
  const model = premium
    ? (cfg.ai_model_premium ?? "gemini-3.7-flash")
    : (cfg.ai_model ?? "gemini-3.1-flash-lite");

  const encoder = new TextEncoder();
  let full = "";

  const stream = new ReadableStream({
    async start(controller) {
      const send = (obj: unknown) =>
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));

      try {
        const usage = await provider.stream(
          { system: SYSTEM_PROMPT, turns, model, maxOutputTokens: maxOut },
          (chunk) => {
            full += chunk;
            send({ delta: chunk });
          },
        );

        // An empty answer is a failure, not a cheap success. Refund it.
        if (!full.trim()) {
          await refund("provider returned empty");
          send({ error: "provider_failed" });
          controller.close();
          return;
        }

        const { data: inserted } = await admin
          .from("ai_messages")
          .insert([
            { conversation_id: conversationId, role: "user",
              content: message, status: "complete", user_id: user.id },
            { conversation_id: conversationId, role: "assistant",
              content: full, status: "complete", user_id: user.id },
          ])
          .select("id");

        // Name the conversation from its opening question. The schema
        // expects this ("the edge function derives a short title") and
        // nothing else does it — without it every row in the member's
        // history reads "New conversation" and the list is useless.
        //
        // First exchange only: a title that rewrote itself on every send
        // would make the history shuffle under the member's thumb.
        if (!convo.title) {
          const title = message
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 60);
          await admin
            .from("ai_conversations")
            .update({ title: title + (message.length > 60 ? "…" : "") })
            .eq("id", conversationId);
        }

        // Settle the pessimistic estimate down to what was really spent.
        const actual = costMicros(usage, priceIn, priceOut);
        await admin.rpc("ai_settle_cost", {
          p_user: user.id,
          p_conversation_id: conversationId,
          p_message_id: inserted?.[1]?.id ?? null,
          p_estimate_micros: estimate,
          p_actual_micros: actual,
        });

        const { data: bal } = await admin
          .rpc("ai_my_balance_for", { p_user: user.id })
          .maybeSingle()
          .then((r) => r, () => ({ data: null }));

        send({ done: true, balance: bal ?? null });
        controller.close();
      } catch (e) {
        const err = e as AiProviderError;
        const kind = err?.kind ?? "retryable";

        // The member pays for nothing that failed, whatever the cause.
        await refund(`provider ${kind}`);

        if (kind === "suspended") {
          // Stop the whole app hammering a dead endpoint, and tell the
          // founder. Members get "temporarily unavailable" — never the
          // provider's wording, which can name billing state.
          await admin.rpc("ai_trip_service_suspended", {
            p_reason: String(err?.message ?? "").slice(0, 500),
          });
        }
        console.error("advent-ai provider failure:", kind, err?.message);

        send({
          error: kind === "suspended" ? "service_suspended" : "provider_failed",
        });
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...CORS,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    },
  });
});
