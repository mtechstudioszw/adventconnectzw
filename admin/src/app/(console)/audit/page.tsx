"use client";

import { useState } from "react";
import { Queue } from "@/components/Queue";
import { fmtAgo, fmtDate } from "@/lib/format";

type AuditRow = {
  id: number;
  actor_name: string | null;
  actor_role: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  note: string | null;
  created_at: string;
};

/** Actions worth being able to isolate quickly when something looks wrong. */
const FILTERS = [
  "all",
  "maintenance_on",
  "maintenance_off",
  "ban",
  "broadcast",
  "staff_role",
] as const;

const LABELS: Record<(typeof FILTERS)[number], string> = {
  all: "Everything",
  maintenance_on: "App off",
  maintenance_off: "App on",
  ban: "Bans",
  broadcast: "Broadcasts",
  staff_role: "Role changes",
};

/** Colour only the actions that matter at a glance. */
function tone(action: string): string {
  if (action.startsWith("maintenance_on") || action.includes("ban")) return "red";
  if (action.startsWith("maintenance_off") || action.includes("approve")) return "green";
  if (action.includes("role") || action.includes("broadcast")) return "gold";
  return "grey";
}

export default function AuditPage() {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("all");

  return (
    <Queue<AuditRow>
      rpcName="admin_list_audit_log"
      rpcArgs={{ p_limit: 200, p_action: filter === "all" ? null : filter }}
      title="Audit log"
      sub="Every action taken from this console, with who did it. This is the record that makes hiring safe."
      columns={["When", "Who", "Action", "Details"]}
      emptyTitle="Nothing recorded yet"
      emptySub={
        filter === "all"
          ? "Actions appear here as soon as anyone uses the console."
          : "No actions of this kind."
      }
      toolbar={
        <div className="segmented" role="tablist">
          {FILTERS.map((f) => (
            <button
              key={f}
              type="button"
              role="tab"
              aria-selected={f === filter}
              className={f === filter ? "on" : ""}
              onClick={() => setFilter(f)}
            >
              {LABELS[f]}
            </button>
          ))}
        </div>
      }
      row={(r) => (
        <tr key={r.id}>
          <td className="nowrap">
            {fmtAgo(r.created_at)}
            <div className="meta">{fmtDate(r.created_at)}</div>
          </td>
          <td>
            <b>{r.actor_name ?? "—"}</b>
            {r.actor_role ? <div className="meta">{r.actor_role}</div> : null}
          </td>
          <td>
            <span className={`chip ${tone(r.action)}`}>{r.action.replace(/_/g, " ")}</span>
          </td>
          <td>
            {r.target_type ? (
              <div className="meta">
                {r.target_type}
                {r.target_id ? ` · ${r.target_id}` : ""}
              </div>
            ) : null}
            {r.note ? <div style={{ fontSize: 13 }}>{r.note}</div> : null}
          </td>
        </tr>
      )}
      deps={[filter]}
    />
  );
}
