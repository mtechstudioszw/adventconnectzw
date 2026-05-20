/**
 * WhatsApp sender for the admin panel.
 *
 * Uses the Meta WhatsApp Cloud API (Graph) — same surface as the
 * official WhatsApp Business API but without self-hosting a BSP. We
 * deliberately use the "text" message type rather than templates so
 * the admin can send free-form copy; this REQUIRES that the user
 * messaged us within the past 24h, which approval/rejection on the
 * applicant's submission always satisfies (they just applied).
 *
 * If you need to message a user OUTSIDE that 24h window you must
 * switch to a pre-approved template (see Meta docs) — this helper
 * intentionally does NOT do that today because we don't have approved
 * templates yet.
 *
 * Required env (all optional — if missing, sendWhatsapp() is a no-op):
 *   WHATSAPP_PHONE_ID  Phone number ID from Meta WhatsApp Manager
 *   WHATSAPP_TOKEN     Long-lived access token (System User token)
 *
 * Country code normalization: Meta expects E.164 without the leading
 * "+". `27821234567` is good; `+27 (82) 123-4567` is not. We strip
 * everything but digits before sending.
 */

export type WhatsappPayload = {
  to: string;
  message: string;
};

export type WhatsappResult =
  | { ok: true; id: string }
  | { ok: false; reason: "missing_config" | "no_number" | "send_failed"; detail?: string };

export async function sendWhatsapp(
  payload: WhatsappPayload,
): Promise<WhatsappResult> {
  const phoneId = process.env.WHATSAPP_PHONE_ID;
  const token = process.env.WHATSAPP_TOKEN;
  if (!phoneId || !token) {
    console.warn(
      "[notify/whatsapp] skipped — WHATSAPP_PHONE_ID or WHATSAPP_TOKEN not set.",
    );
    return { ok: false, reason: "missing_config" };
  }
  const digits = payload.to.replace(/\D/g, "");
  if (digits.length < 9) {
    return { ok: false, reason: "no_number", detail: "phone too short" };
  }
  try {
    const response = await fetch(
      `https://graph.facebook.com/v20.0/${phoneId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to: digits,
          type: "text",
          text: { body: payload.message },
        }),
      },
    );
    if (!response.ok) {
      const body = await response.text();
      console.warn(
        `[notify/whatsapp] graph ${response.status}: ${body.slice(0, 240)}`,
      );
      return { ok: false, reason: "send_failed", detail: body };
    }
    const data = (await response.json()) as {
      messages?: Array<{ id: string }>;
    };
    return { ok: true, id: data.messages?.[0]?.id ?? "" };
  } catch (err) {
    console.warn("[notify/whatsapp] threw:", err);
    return { ok: false, reason: "send_failed", detail: String(err) };
  }
}
