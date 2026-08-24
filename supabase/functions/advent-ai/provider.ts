// =====================================================================
//  Advent AI — provider abstraction.
//
//  One interface, one implementation (Gemini) today. The brief (§4) asks
//  that the provider be swappable, and the shape below is what that
//  costs: everything provider-specific — endpoint, auth, request shape,
//  stream framing, usage reporting, error taxonomy — lives behind
//  `AiProvider`. `index.ts` never names Gemini.
//
//  Adding a provider means writing one more object of this shape and a
//  line in `getProvider`. Nothing else changes.
//
//  ## The error taxonomy is the important part
//
//  Not all failures mean the same thing, and treating them alike is how
//  a founder's expired card turns into every member being told they are
//  out of credit. Three outcomes, and the caller does something
//  different with each:
//
//    retryable  — transient. Refund the unit, tell the member to try
//                 again shortly. Nothing is wrong with the service.
//    fatal      — this request was bad (too long, blocked content).
//                 Refund the unit. Do not retry; it will fail again.
//    suspended  — the PROVIDER is refusing us: billing lapsed, quota
//                 exhausted, key revoked, account suspended. Refund the
//                 unit, trip ai_service_state so the app stops hammering
//                 a dead endpoint, and alert the founder. This one is
//                 never the member's fault and must never be presented
//                 as their problem.
// =====================================================================
// @ts-nocheck

export type AiFailureKind = "retryable" | "fatal" | "suspended";

export class AiProviderError extends Error {
  constructor(
    public readonly kind: AiFailureKind,
    message: string,
    public readonly status?: number,
  ) {
    super(message);
    this.name = "AiProviderError";
  }
}

/// One turn in the conversation as the provider sees it.
export interface AiTurn {
  role: "user" | "assistant";
  content: string;
}

/// What the provider actually charged us for. Real numbers from the
/// provider's own usage report — never estimated from string length,
/// because the ledger is what bounds the founder's exposure and an
/// estimate that drifts low is an unbounded bill.
export interface AiUsage {
  inputTokens: number;
  outputTokens: number;
}

export interface AiRequest {
  system: string;
  turns: AiTurn[];
  model: string;
  maxOutputTokens: number;
}

export interface AiProvider {
  readonly id: string;
  /// Streams text chunks as they arrive; resolves with final usage.
  stream(
    req: AiRequest,
    onChunk: (text: string) => void,
  ): Promise<AiUsage>;
}

// ---------------------------------------------------------------------
//  Gemini
// ---------------------------------------------------------------------

const GEMINI_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

/// Map an HTTP status + body onto the taxonomy above.
///
/// The distinction that matters is 429: Gemini returns it both for
/// "you're going too fast" (retryable) and for "your free-tier daily
/// quota is gone" (suspended). The body text is the only thing that
/// separates them, so it is read rather than assumed.
function classify(status: number, body: string): AiFailureKind {
  const b = body.toLowerCase();

  if (
    status === 401 || status === 403 ||
    b.includes("api key not valid") ||
    b.includes("permission_denied") ||
    b.includes("billing") ||
    b.includes("consumer_suspended") ||
    b.includes("account is suspended")
  ) {
    return "suspended";
  }

  if (status === 429) {
    // Per-day/per-project quota exhaustion is a funding problem, not a
    // pacing problem, and retrying it just burns latency.
    return b.includes("quota") && !b.includes("per minute")
      ? "suspended"
      : "retryable";
  }

  if (status >= 500) return "retryable";
  return "fatal";
}

export const geminiProvider: AiProvider = {
  id: "gemini",

  async stream(req, onChunk): Promise<AiUsage> {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) {
      // A missing key is a deployment fault, not a member fault. Tripping
      // "suspended" is right: nobody can be served until it is fixed, and
      // the founder gets told rather than members getting nonsense.
      throw new AiProviderError(
        "suspended",
        "GEMINI_API_KEY is not set on the function",
      );
    }

    // Gemini uses `model`/`user` rather than `assistant`/`user`, and
    // takes the system instruction out of band.
    const contents = req.turns.map((t) => ({
      role: t.role === "assistant" ? "model" : "user",
      parts: [{ text: t.content }],
    }));

    const url =
      `${GEMINI_BASE}/${req.model}:streamGenerateContent?alt=sse&key=${key}`;

    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: req.system }] },
          contents,
          generationConfig: {
            maxOutputTokens: req.maxOutputTokens,
            temperature: 0.7,
          },
          // The app has its own scope and safety rules in the prompt and
          // its own moderation elsewhere. These are left at Gemini's
          // defaults deliberately — loosening them on a church app is
          // not a decision to make quietly in a config object.
        }),
      });
    } catch (e) {
      // DNS, TLS, socket — never reached the provider.
      throw new AiProviderError("retryable", `network: ${e}`);
    }

    if (!res.ok || !res.body) {
      const body = await res.text().catch(() => "");
      throw new AiProviderError(
        classify(res.status, body),
        `gemini ${res.status}: ${body.slice(0, 300)}`,
        res.status,
      );
    }

    // ---- SSE ---------------------------------------------------------
    // Chunks do not respect line boundaries, so a partial line is held
    // back rather than parsed. Parsing a half-received JSON object is
    // the classic streaming bug and shows up as random dropped words.
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let usage: AiUsage = { inputTokens: 0, outputTokens: 0 };

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) continue;

        const payload = trimmed.slice(5).trim();
        if (!payload || payload === "[DONE]") continue;

        let parsed: any;
        try {
          parsed = JSON.parse(payload);
        } catch {
          continue; // A malformed frame must not kill a good stream.
        }

        const text = parsed?.candidates?.[0]?.content?.parts
          ?.map((p: any) => p?.text ?? "")
          .join("") ?? "";
        if (text) onChunk(text);

        // Usage arrives on the final frames and is cumulative, so the
        // last one seen wins rather than being summed.
        const um = parsed?.usageMetadata;
        if (um) {
          usage = {
            inputTokens: um.promptTokenCount ?? usage.inputTokens,
            outputTokens: um.candidatesTokenCount ?? usage.outputTokens,
          };
        }
      }
    }

    return usage;
  },
};

/// Resolve the configured provider. `ai_provider` in app_config.
export function getProvider(id: string): AiProvider {
  switch (id) {
    case "gemini":
      return geminiProvider;
    default:
      // Fail loudly rather than silently falling back — a typo in config
      // that quietly routes every member to a different provider (and a
      // different bill) is worse than the feature being down.
      throw new AiProviderError(
        "suspended",
        `unknown ai_provider: ${id}`,
      );
  }
}

/// Convert real token usage into micros of USD, using the prices held in
/// app_config so a provider price change is a dashboard edit.
export function costMicros(
  usage: AiUsage,
  inPerMTok: number,
  outPerMTok: number,
): number {
  const micros =
    (usage.inputTokens / 1_000_000) * inPerMTok +
    (usage.outputTokens / 1_000_000) * outPerMTok;
  // Round UP. Under-recording spend is the direction that hurts — it
  // lets the global ceilings drift above what was actually billed.
  return Math.ceil(micros);
}
