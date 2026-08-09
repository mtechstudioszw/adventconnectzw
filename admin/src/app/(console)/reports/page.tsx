"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton, Segmented, StatusChip } from "@/components/ui";
import { fmtAgo } from "@/lib/format";
import { useSession } from "@/lib/session";

type Report = {
  id: number;
  content_type: string;
  content_id: string;
  reason: string;
  details: string | null;
  reporter_name: string;
  status: string;
  action_taken: string | null;
  created_at: string;
};

const FILTERS = ["pending", "actioned", "dismissed", "all"] as const;

export default function ReportsPage() {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("pending");
  const { can } = useSession();

  return (
    <Queue<Report>
      rpcName="admin_list_reports"
      rpcArgs={{ p_status: filter }}
      title="Reports"
      sub="Reported posts, messages and accounts. Replying tells the reporter it was looked at."
      columns={["Reported", "Reason", "Reporter", "Status", ""]}
      emptyTitle={filter === "pending" ? "No open reports" : "Nothing here"}
      emptySub={
        filter === "pending" ? "Nothing is waiting to be looked at." : undefined
      }
      toolbar={<Segmented options={FILTERS} value={filter} onChange={setFilter} />}
      row={(r, { act, ask }) => {
        // A report against a person carries the account id, so it can be
        // actioned and the account banned in one step rather than copying an
        // id across to the Members screen.
        const banId =
          r.content_type === "user" || r.content_type === "profile" ? r.content_id : "";
        const open = r.status === "pending";

        return (
          <tr key={r.id}>
            <td>
              <b>{r.content_type}</b>
              <div className="meta mono">{r.content_id}</div>
            </td>
            <td>
              {r.reason}
              {r.details ? <div className="meta">{r.details}</div> : null}
            </td>
            <td>
              {r.reporter_name}
              <div className="meta">{fmtAgo(r.created_at)}</div>
            </td>
            <td>
              <StatusChip status={r.status} />
              {r.action_taken ? <div className="meta">{r.action_taken}</div> : null}
            </td>
            <td className="nowrap">
              {!open ? (
                <span className="faint">—</span>
              ) : (
                <div className="actions">
                  <BusyButton
                    className="btn ghost sm"
                    onClick={async () => {
                      const reply = await ask({
                        title: "Reply to the reporter",
                        sub: "Lands in their notifications. The report stays open.",
                        input: { placeholder: "Type your reply…", multiline: true, required: true },
                        confirmLabel: "Send reply",
                      });
                      if (!reply) return;
                      await act(
                        () => rpc("admin_reply_report", { p_report_id: r.id, p_reply: reply }),
                        "Reply sent.",
                      );
                    }}
                  >
                    Reply
                  </BusyButton>

                  <BusyButton
                    className="btn green sm"
                    onClick={async () => {
                      const note = await ask({
                        title: "Resolve report",
                        sub: "What did you do about it? This is recorded.",
                        input: { placeholder: "e.g. Removed the post" },
                        confirmLabel: "Resolve",
                        tone: "green",
                      });
                      if (note === null) return;
                      await act(
                        () =>
                          rpc("admin_resolve_report", {
                            p_report_id: r.id,
                            p_status: "actioned",
                            p_action: note || "Actioned",
                          }),
                        "Report resolved.",
                      );
                    }}
                  >
                    Resolve
                  </BusyButton>

                  {banId && can("owner") ? (
                    <BusyButton
                      className="btn red sm"
                      onClick={async () => {
                        const note = await ask({
                          title: "Ban the account and resolve",
                          sub: "Bans the reported member and marks this report actioned.",
                          input: { placeholder: "Reason (recorded)", required: true },
                          confirmLabel: "Ban",
                          tone: "red",
                        });
                        if (!note) return;
                        await act(
                          () =>
                            rpc("admin_resolve_report", {
                              p_report_id: r.id,
                              p_status: "actioned",
                              p_action: `Banned: ${note}`,
                              p_ban_user_id: banId,
                            }),
                          "Account banned and report resolved.",
                        );
                      }}
                    >
                      Ban &amp; resolve
                    </BusyButton>
                  ) : null}

                  <BusyButton
                    className="btn ghost sm"
                    onClick={() =>
                      act(
                        () =>
                          rpc("admin_resolve_report", {
                            p_report_id: r.id,
                            p_status: "dismissed",
                            p_action: "Dismissed — no action",
                          }),
                        "Report dismissed.",
                      )
                    }
                  >
                    Dismiss
                  </BusyButton>
                </div>
              )}
            </td>
          </tr>
        );
      }}
      deps={[can("owner")]}
    />
  );
}
