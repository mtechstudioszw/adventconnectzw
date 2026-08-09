"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton, Segmented, StatusChip } from "@/components/ui";
import { fmtAgo } from "@/lib/format";

type Feedback = {
  id: number;
  user_name: string;
  category: string | null;
  platform: string | null;
  app_version: string | null;
  subject: string | null;
  body: string;
  status: string;
  resolution_note: string | null;
  created_at: string;
};

const FILTERS = ["new", "resolved", "all"] as const;

export default function FeedbackPage() {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("new");

  return (
    <Queue<Feedback>
      rpcName="admin_list_feedback"
      rpcArgs={{ p_status: filter }}
      title="Feedback"
      sub="What members are telling you. A reply lands in their notifications and closes the item."
      columns={["From", "Message", "Status", ""]}
      emptyTitle={filter === "new" ? "No new feedback" : "Nothing here"}
      emptySub={filter === "new" ? "Everyone who wrote in has had a reply." : undefined}
      toolbar={<Segmented options={FILTERS} value={filter} onChange={setFilter} />}
      row={(f, { act, ask }) => (
        <tr key={f.id}>
          <td>
            <b>{f.user_name}</b>
            <div className="meta">
              {[f.category, f.platform, f.app_version].filter(Boolean).join(" · ")}
            </div>
            <div className="meta">{fmtAgo(f.created_at)}</div>
          </td>
          <td>
            <b>{f.subject || "(no subject)"}</b>
            <div style={{ marginTop: 2 }}>{f.body}</div>
            {f.resolution_note ? (
              <div className="meta" style={{ marginTop: 4 }}>
                ↳ replied: {f.resolution_note}
              </div>
            ) : null}
          </td>
          <td>
            <StatusChip status={f.status} />
          </td>
          <td className="nowrap">
            {f.status === "resolved" ? (
              <span className="faint">—</span>
            ) : (
              <BusyButton
                className="btn primary sm"
                onClick={async () => {
                  const reply = await ask({
                    title: `Reply to ${f.user_name}`,
                    sub: "They get it as a notification, and this feedback is marked resolved.",
                    input: { placeholder: "Type your reply…", multiline: true, required: true },
                    confirmLabel: "Send reply",
                  });
                  if (!reply) return;
                  await act(
                    () => rpc("admin_reply_feedback", { p_feedback_id: f.id, p_reply: reply }),
                    "Reply sent.",
                  );
                }}
              >
                Reply
              </BusyButton>
            )}
          </td>
        </tr>
      )}
    />
  );
}
