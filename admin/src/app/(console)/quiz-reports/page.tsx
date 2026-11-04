"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton, Segmented } from "@/components/ui";
import { fmtDay, truncate } from "@/lib/format";

/**
 * Questions members flagged from the quiz (patch_314). Dismiss the report,
 * or take a bad question out of the game. Generated questions (built on the
 * phone from the Bible) have no row to unpublish — the report still tells you
 * which template to fix.
 */
type Report = {
  id: number;
  question_id: string;
  is_generated: boolean;
  question_text: string | null;
  reason: string | null;
  reporter: string | null;
  created_at: string;
  resolved: boolean;
  options: string[] | null;
  correct_index: number | null;
  explanation: string | null;
  reference: string | null;
  is_published: boolean | null;
};

const FILTERS = ["open", "resolved"] as const;
type Filter = (typeof FILTERS)[number];

export default function QuizReportsPage() {
  const [filter, setFilter] = useState<Filter>("open");

  return (
    <Queue<Report>
      rpcName="admin_list_quiz_reports"
      rpcArgs={{ p_resolved: filter === "resolved" }}
      title="Quiz reports"
      sub="Questions members said were wrong or unclear."
      columns={["Question", "Report", ""]}
      emptyTitle={filter === "open" ? "No open reports" : "Nothing resolved yet"}
      emptySub="Members report a question from the answer screen in the quiz."
      toolbar={
        <Segmented
          options={FILTERS}
          value={filter}
          onChange={setFilter}
          labels={{ open: "Open", resolved: "Resolved" }}
        />
      }
      deps={[filter]}
      row={(r, { act, ask }) => (
        <tr key={r.id}>
          <td style={{ maxWidth: 520 }}>
            <b>{r.question_text ?? `Question ${r.question_id}`}</b>
            {r.options && r.options.length ? (
              <ol className="meta" style={{ margin: "6px 0 0 18px", padding: 0 }}>
                {r.options.map((o, i) => (
                  <li key={i} style={{ fontWeight: i === r.correct_index ? 700 : 400 }}>
                    {o}
                    {i === r.correct_index ? " ✓" : ""}
                  </li>
                ))}
              </ol>
            ) : null}
            <div className="meta">
              {[
                r.is_generated ? "Generated question" : `Question #${r.question_id}`,
                r.reference,
                r.is_published === false ? "UNPUBLISHED" : null,
              ]
                .filter(Boolean)
                .join(" · ")}
            </div>
            {r.explanation ? <div className="meta">{truncate(r.explanation, 240)}</div> : null}
          </td>
          <td>
            {r.reason ? <div>{truncate(r.reason, 300)}</div> : <span className="faint">No reason given</span>}
            <div className="meta">
              {r.reporter ?? "A member"} · {fmtDay(r.created_at)}
            </div>
          </td>
          <td className="nowrap">
            {!r.resolved ? (
              <div className="actions">
                <BusyButton
                  className="btn ghost sm"
                  onClick={() =>
                    act(
                      () => rpc("admin_resolve_quiz_report", { p_id: r.id, p_unpublish: false, p_note: null }),
                      "Report dismissed.",
                    )
                  }
                >
                  Dismiss
                </BusyButton>
                {!r.is_generated && r.is_published !== false && r.options ? (
                  <BusyButton
                    className="btn red sm"
                    onClick={async () => {
                      const ok = await ask({
                        title: "Take this question out of the quiz?",
                        sub: "It stops appearing in every mode. You can fix and republish it later.",
                        confirmLabel: "Unpublish",
                        tone: "red",
                      });
                      if (ok === null) return;
                      await act(
                        () => rpc("admin_resolve_quiz_report", { p_id: r.id, p_unpublish: true, p_note: null }),
                        "Question unpublished.",
                      );
                    }}
                  >
                    Unpublish
                  </BusyButton>
                ) : null}
              </div>
            ) : (
              <span className="chip green">RESOLVED</span>
            )}
          </td>
        </tr>
      )}
    />
  );
}
