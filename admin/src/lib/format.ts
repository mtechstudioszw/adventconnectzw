/** Formatting helpers. Harare time, English, no library. */

const HARARE = "Africa/Harare";

export function fmtDate(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString("en-GB", {
    timeZone: HARARE,
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function fmtDay(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("en-GB", {
    timeZone: HARARE,
    day: "numeric",
    month: "short",
  });
}

/**
 * "3 minutes ago". Queue work is about recency far more than about clock
 * time — whether a report came in during this shift is the question being
 * asked, and an absolute timestamp makes you do that arithmetic yourself.
 */
export function fmtAgo(value: string | null | undefined): string {
  if (!value) return "—";
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return "—";
  const secs = Math.round((Date.now() - then) / 1000);
  if (secs < 0) return "just now";
  if (secs < 60) return "just now";
  const mins = Math.round(secs / 60);
  if (mins < 60) return `${mins} min${mins === 1 ? "" : "s"} ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days} day${days === 1 ? "" : "s"} ago`;
  return fmtDate(value);
}

export function fmtNum(value: number | string | null | undefined): string {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n.toLocaleString("en-GB") : "0";
}

export function pct(part: number, total: number): number {
  if (!total) return 0;
  return Math.round((part / total) * 100);
}

/** Digits only, for wa.me links. Returns "" when there is no usable number. */
export function waNumber(phone: string | null | undefined): string {
  return String(phone ?? "").replace(/[^0-9]/g, "");
}

export function openWhatsApp(phone: string | null | undefined, text?: string) {
  const n = waNumber(phone);
  if (!n) return;
  const suffix = text ? `?text=${encodeURIComponent(text)}` : "";
  window.open(`https://wa.me/${n}${suffix}`, "_blank", "noopener");
}

/**
 * A URL that is safe to put in an `href` or `src`, or `null`.
 *
 * Some of what this console renders is **submitted by members** — the link on
 * a Watch channel submission, the cover photo on a news story. A
 * `javascript:` URL in one of those runs in the session of whoever opens the
 * queue, and the people who open these queues can ban members, broadcast to
 * everyone and take the app offline. That is worth a scheme check even though
 * it needs a moderator to click it.
 *
 * Allowing only http(s) also rules out `data:` (inline HTML payloads) and
 * `blob:`.
 */
export function safeUrl(value: string | null | undefined): string | null {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  try {
    const parsed = new URL(raw);
    return parsed.protocol === "http:" || parsed.protocol === "https:"
      ? parsed.toString()
      : null;
  } catch {
    // Not an absolute URL at all. Refuse rather than guess a scheme — a
    // relative href here would point at the console itself.
    return null;
  }
}

export function initials(value: string | null | undefined): string {
  const s = String(value ?? "").trim();
  if (!s) return "?";
  const parts = s.split(/[\s@.]+/).filter(Boolean);
  const first = parts[0]?.[0] ?? "";
  const second = parts.length > 1 ? parts[1][0] : "";
  return (first + second).toUpperCase() || "?";
}

export function truncate(value: string | null | undefined, max: number): string {
  const s = String(value ?? "");
  return s.length > max ? `${s.slice(0, max)}…` : s;
}

/**
 * `datetime-local` gives "2026-08-09T21:30" with no zone, and the browser
 * means *local* time by it. Everyone using this console is in Harare, and
 * `admin_set_maintenance` takes a timestamptz — so this converts through the
 * real Date rather than pasting the string into SQL and hoping.
 */
export function localInputToIso(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** The inverse, for filling the input back in from a stored timestamp. */
export function isoToLocalInput(value: string | null | undefined): string {
  if (!value) return "";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(
    d.getHours(),
  )}:${pad(d.getMinutes())}`;
}
