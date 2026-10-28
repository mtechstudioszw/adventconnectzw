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
  // patch_279 — what was reported and who is behind it. Absent (undefined)
  // until the patch runs; the page then falls back to the bare id.
  content_title?: string | null;
  content_preview?: string | null;
  content_state?: string | null;
  reported_user_id?: string | null;
  reported_user_name?: string | null;
  reported_user_banned?: boolean;
  open_reports_on_content?: number;
};

const TYPE_LABEL: Record<string, string> = {
  job: "Job",
  product: "Product",
  seller: "Store",
  page: "Page",
  post: "Post",
  user: "Member",
  profile: "Member",
  message: "Message",
  comment: "Comment",
  event: "Event",
  prayer: "Prayer",
  news: "News",
  story: "Story",
};

// Types patch_279 can take down (people are handled by the ban).
const REMOVABLE = new Set(["job", "product", "seller", "page", "post"]);

const FILTERS = ["pending", "actioned", "dismissed", "all"] as const;

export default function ReportsPage() {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("pending");
  const { can } = useSession();

  return (
    <Queue<Report>
      rpcName="admin_list_reports"
      rpcArgs={{ p_status: filter }}
      title="Reports"
      sub="Reported jobs, products, stores, posts and accounts. Remove takes the item down; Remove & ban also bans whoever posted it and takes down everything else they have live."
      columns={["Reported", "Reason", "Posted by", "Reporter", "Status", ""]}
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
          r.content_type === "user" || r.content_type === "profile"
            ? r.content_id
            : (r.reported_user_id ?? "");
        const open = r.status === "pending";
        const enriched = r.content_title !== undefined;
        const removable = enriched && REMOVABLE.has(r.content_type);
        const many = (r.open_reports_on_content ?? 0) > 1;


        return (
          <tr key={r.id}>
            <td style={{ maxWidth: 320 }}>
              <div className="meta">{TYPE_LABEL[r.content_type] ?? r.content_type}</div>
              <b>{r.content_title || r.content_id}</b>
              {r.content_preview ? (
                <div className="meta">{r.content_preview}</div>
              ) : null}
              <div className="meta">
                {r.content_state ? <>Now: {r.content_state} · </> : null}
                <span className="mono">#{r.content_id}</span>
                {many ? <> · <b>{r.open_reports_on_content} open reports</b></> : null}
              </div>
            </td>
            <td>
              {r.reason}
              {r.details ? <div className="meta">{r.details}</div> : null}
            </td>
            <td>
              {r.reported_user_name ?? (banId ? "Member" : "—")}
              {r.reported_user_banned ? <div className="meta">Banned</div> : null}
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

                  {removable ? (
                    <BusyButton
                      className="btn red sm"
                      onClick={async () => {
                        const reason = await ask({
                          title: `Remove this ${(TYPE_LABEL[r.content_type] ?? "item").toLowerCase()}`,
                          sub: "It comes down for everyone and the person who posted it is told why. Every open report on it is closed.",
                          input: { placeholder: "Reason they will see, e.g. Asked applicants for money", required: true },
                          confirmLabel: "Remove",
                          tone: "red",
                        });
                        if (!reason) return;
                        await act(
                          () =>
                            rpc("admin_takedown_report", {
                              p_report_id: r.id,
                              p_reason: reason,
                              p_ban: false,
                            }),
                          "Removed and report closed.",
                        );
                      }}
                    >
                      Remove
                    </BusyButton>
                  ) : null}

                  {enriched && banId && !r.reported_user_banned && can("owner") ? (
                    <BusyButton
                      className="btn red sm"
                      onClick={async () => {
                        const reason = await ask({
                          title: "Remove and ban",
                          sub: `Bans ${r.reported_user_name ?? "this member"} and takes down everything they have live — jobs, store and listings. They are notified.`,
                          input: { placeholder: "Reason (recorded and shown to them)", required: true },
                          confirmLabel: "Remove & ban",
                          tone: "red",
                        });
                        if (!reason) return;
                        await act(
                          () =>
                            rpc("admin_takedown_report", {
                              p_report_id: r.id,
                              p_reason: reason,
                              p_ban: true,
                            }),
                          "Removed, account banned, report closed.",
                        );
                      }}
                    >
                      Remove &amp; ban
                    </BusyButton>
                  ) : null}

                  {!enriched && banId && can("owner") ? (
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
