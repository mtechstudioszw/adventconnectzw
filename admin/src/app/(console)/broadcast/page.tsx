"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { useAsk } from "@/components/Dialog";
import { useToast } from "@/components/Toast";
import { CountedField, ErrorBox, Note, PageHead } from "@/components/ui";
import { useSession } from "@/lib/session";
import { fmtNum } from "@/lib/format";

const SEGMENTS = [
  "all",
  "Harare",
  "Bulawayo",
  "Manicaland",
  "Mashonaland Central",
  "Mashonaland East",
  "Mashonaland West",
  "Masvingo",
  "Matabeleland North",
  "Matabeleland South",
  "Midlands",
] as const;

export default function BroadcastPage() {
  const { role } = useSession();
  const ask = useAsk();
  const toast = useToast();

  const [segment, setSegment] = useState<string>("all");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<number | null>(null);

  if (role !== "owner") {
    return (
      <div>
        <PageHead title="Broadcast" />
        <Note>
          Only an <strong>owner</strong> can send a message to the whole
          membership.
        </Note>
      </div>
    );
  }

  const send = async () => {
    const t = title.trim();
    const b = body.trim();
    if (!t || !b) {
      setError("A title and a message are both required.");
      return;
    }

    const where = segment === "all" ? "every member" : `everyone in ${segment}`;
    const confirmed = await ask({
      title: `Send to ${where}?`,
      sub: "This pushes a notification to their phone. It cannot be recalled once sent.",
      confirmLabel: "Send broadcast",
      typeToConfirm: segment === "all" ? "SEND" : undefined,
    });
    if (confirmed === null) return;

    setBusy(true);
    setError(null);
    try {
      const n = await rpc<number>("admin_broadcast", {
        p_title: t,
        p_body: b,
        p_segment: segment,
      });
      setSentTo(Number(n ?? 0));
      setTitle("");
      setBody("");
      toast.ok(`Sent to ${fmtNum(n)} member(s).`);
    } catch (e) {
      const m = e instanceof Error ? e.message : "Could not send.";
      setError(m);
      toast.err(m);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="stack" style={{ maxWidth: 620 }}>
      <PageHead
        title="Broadcast"
        sub="A notice to every member, or to one province. It arrives as a notification and a push."
      />

      <div className="card card-pad" style={{ display: "grid", gap: 16 }}>
        <div className="field">
          <label className="label" htmlFor="segment">
            Who gets it
          </label>
          <select
            id="segment"
            className="select"
            value={segment}
            onChange={(e) => setSegment(e.target.value)}
          >
            {SEGMENTS.map((s) => (
              <option key={s} value={s}>
                {s === "all" ? "All members" : s}
              </option>
            ))}
          </select>
        </div>

        <CountedField
          label="Title"
          value={title}
          onChange={setTitle}
          max={80}
          placeholder="e.g. Sabbath programme this week"
        />

        <CountedField
          label="Message"
          value={body}
          onChange={setBody}
          max={500}
          textarea
          rows={5}
          placeholder="Write the notice…"
        />

        {error ? <ErrorBox message={error} /> : null}

        <div className="row">
          <button
            className="btn primary"
            onClick={() => void send()}
            disabled={busy || !title.trim() || !body.trim()}
          >
            {busy ? <span className="spinner" /> : null}
            {busy ? "Sending…" : "Send broadcast"}
          </button>
          {sentTo != null ? (
            <span className="meta">Last broadcast reached {fmtNum(sentTo)} member(s).</span>
          ) : null}
        </div>
      </div>

      <Note>
        A broadcast is not an essential notification, so for any member who has
        turned Sabbath mode on it is <strong>dropped, not delayed</strong>, while
        their quiet window lasts — they will never see it. Send outside those
        hours if it matters. Maintenance notices, direct messages and payment
        receipts always go through.
      </Note>
    </div>
  );
}
