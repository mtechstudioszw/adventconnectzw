/**
 * Transactional email sender for the admin panel.
 *
 * We use the Resend HTTP API rather than an SMTP library so the admin
 * deploy stays edge-friendly (no nodemailer / TCP). Resend was chosen
 * because it's the simplest path: one API key, one fetch call, deliver-
 * ability sorted for us. Any other transactional provider with a
 * similar HTTP API (Postmark, SendGrid v3, etc.) is a drop-in
 * replacement — only `sendViaResend` needs to change.
 *
 * Required env (all optional — if missing, sendEmail() is a no-op):
 *   RESEND_API_KEY   API key from https://resend.com (server-side only)
 *   NOTIFY_FROM      "Advent Connect ZW <hello@adventconnect.zw>"
 *
 * Domain MUST be verified in Resend before From: addresses outside
 * resend.dev will deliver. Until that's done set NOTIFY_FROM to
 * something like "onboarding@resend.dev" so test sends still work.
 */

export type EmailPayload = {
  to: string;
  subject: string;
  text: string;
  html?: string;
};

export type EmailResult =
  | { ok: true; id: string }
  | { ok: false; reason: "missing_config" | "send_failed"; detail?: string };

export async function sendEmail(payload: EmailPayload): Promise<EmailResult> {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.NOTIFY_FROM;
  if (!apiKey || !from) {
    // Soft no-op so the approve/reject flow keeps working in dev
    // before the admin has configured a sender. We log so the missing
    // config is visible in the server logs.
    console.warn(
      "[notify/email] skipped — RESEND_API_KEY or NOTIFY_FROM not set.",
    );
    return { ok: false, reason: "missing_config" };
  }
  if (!isValidEmail(payload.to)) {
    return { ok: false, reason: "send_failed", detail: "invalid recipient" };
  }
  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: payload.to,
        subject: payload.subject,
        text: payload.text,
        html: payload.html ?? defaultHtml(payload.text),
      }),
    });
    if (!response.ok) {
      const body = await response.text();
      console.warn(
        `[notify/email] resend ${response.status}: ${body.slice(0, 240)}`,
      );
      return { ok: false, reason: "send_failed", detail: body };
    }
    const data = (await response.json()) as { id?: string };
    return { ok: true, id: data.id ?? "" };
  } catch (err) {
    console.warn("[notify/email] threw:", err);
    return { ok: false, reason: "send_failed", detail: String(err) };
  }
}

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

// Resend will auto-fallback if `html` is missing, but providing a tiny
// wrapper keeps the rendering predictable across Gmail / Outlook / Apple
// Mail and lets us style the body without changing every callsite.
function defaultHtml(text: string): string {
  const escaped = text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  return `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1A1A2E;">
      <p style="font-size: 14px; line-height: 1.55; white-space: pre-line;">${escaped}</p>
      <p style="margin-top: 32px; font-size: 12px; color: #7B7F94;">— The Advent Connect ZW team</p>
    </div>
  `.trim();
}
