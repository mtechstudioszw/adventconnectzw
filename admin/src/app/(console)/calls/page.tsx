"use client";

import { useCallback } from "react";
import { rpc } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useSession } from "@/lib/session";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import { ErrorBox, Note, PageHead, Tile, TilesSkeleton } from "@/components/ui";
import { IconRefresh } from "@/components/icons";

/**
 * Voice calls — the same numbers as the app's Calls admin screen
 * (call_admin_metrics, super admin), plus ending a stuck call (audited via
 * admin_end_call, patch_315).
 *
 * The health signal is answered vs total: if it falls, either push (calls
 * not ringing) or TURN (calls not connecting) is broken.
 */
type Metrics = Record<string, unknown>;

const LABELS: Record<string, string> = {
  total_calls: "Calls, all time",
  calls_today: "Calls today",
  calls_7d: "Calls, last 7 days",
  active_now: "Live now",
  ringing_now: "Ringing now",
  direct_calls: "1-to-1 calls",
  group_calls: "Group calls",
  answered: "Answered",
  missed: "Missed",
  rejected: "Declined",
  busy: "Busy",
  failed: "Failed",
  swept: "Cleaned up (stuck)",
  total_minutes: "Minutes, all time",
  avg_seconds: "Average length (s)",
  peak_participants: "Most people in one call",
  relayed_minutes_30d: "Relayed minutes, 30 days",
  minutes_30d: "Minutes, 30 days",
  rate_limit_events_24h: "Rate-limited, 24h",
  push_failures_24h: "Ring pushes failed, 24h",
};

const ALERT = new Set(["failed", "push_failures_24h", "rate_limit_events_24h"]);

type Row = Record<string, unknown>;

export default function CallsPage() {
  const { can } = useSession();
  const toast = useToast();
  const ask = useAsk();
  const load = useCallback(() => rpc<Metrics>("call_admin_metrics"), []);
  const { data, error, loading, reload } = useAsync<Metrics>(load, []);

  const scalars = Object.entries(data ?? {}).filter(
    ([, v]) => typeof v === "number" || typeof v === "string",
  );
  const lists = Object.entries(data ?? {}).filter(([, v]) => Array.isArray(v)) as [string, Row[]][];

  const total = Number(data?.total_calls ?? 0);
  const answered = Number(data?.answered ?? 0);
  const rate = total ? Math.round((answered / total) * 100) : null;

  const endCall = async (id: string) => {
    const ok = await ask({
      title: "End this call for everyone?",
      sub: "Use this only for a call that is stuck. Everyone in it is disconnected.",
      confirmLabel: "End call",
      tone: "red",
    });
    if (ok === null) return;
    try {
      await rpc("admin_end_call", { p_call: id });
      toast.ok("Call ended.");
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Could not end it.");
    }
  };

  return (
    <div>
      <PageHead
        title="Calls"
        sub="How voice calling is doing. Super admin only."
        actions={
          <button className="btn ghost" onClick={reload} disabled={loading}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />
      {error ? <ErrorBox message={error} /> : null}
      {rate !== null ? (
        <Note>
          <b>{rate}%</b> of calls were answered. If this drops suddenly, calls are not ringing
          (push) or not connecting (TURN) — check “Ring pushes failed”.
        </Note>
      ) : null}

      {loading && !data ? (
        <TilesSkeleton count={8} />
      ) : (
        <div className="tiles">
          {scalars.map(([k, v]) => (
            <Tile
              key={k}
              label={LABELS[k] ?? k.replace(/_/g, " ")}
              value={typeof v === "number" ? v : String(v)}
              tone={ALERT.has(k) ? "danger" : undefined}
            />
          ))}
        </div>
      )}

      {lists.map(([k, rows]) =>
        rows.length ? (
          <section key={k} style={{ marginTop: 20 }}>
            <h3 style={{ fontSize: 15, fontWeight: 700, marginBottom: 8 }}>
              {LABELS[k] ?? k.replace(/_/g, " ")}
            </h3>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    {Object.keys(rows[0]).map((c) => (
                      <th key={c}>{c.replace(/_/g, " ")}</th>
                    ))}
                    {can("owner") ? <th /> : null}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r, i) => {
                    const id = (r.id ?? r.call_id) as string | undefined;
                    const live = r.status && r.status !== "ended";
                    return (
                      <tr key={i}>
                        {Object.keys(rows[0]).map((c) => (
                          <td key={c}>{r[c] == null ? "—" : String(r[c])}</td>
                        ))}
                        {can("owner") ? (
                          <td className="nowrap">
                            {id && live ? (
                              <button className="btn red sm" onClick={() => endCall(id)}>
                                End
                              </button>
                            ) : null}
                          </td>
                        ) : null}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>
        ) : null,
      )}
    </div>
  );
}
