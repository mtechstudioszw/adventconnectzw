"use client";

import { useCallback } from "react";
import { rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useBadges } from "./Badges";
import { useToast } from "./Toast";
import { useAsk, type AskOptions } from "./Dialog";
import { Empty, ErrorBox, PageHead, TableSkeleton } from "./ui";
import { IconRefresh } from "./icons";

/**
 * The shape every review queue shares: load a pending list, act on a row,
 * reload, and keep the sidebar badge honest.
 *
 * Six screens were otherwise going to repeat the same load/act/reload cycle
 * with the same three failure modes — a stale list after an action, a badge
 * that keeps counting a cleared item, and an error swallowed into an empty
 * table. Doing it once means fixing it once.
 */
export function Queue<T>({
  rpcName,
  rpcArgs,
  columns,
  row,
  title,
  sub,
  emptyTitle,
  emptySub,
  toolbar,
  deps = [],
}: {
  rpcName: string;
  rpcArgs?: Record<string, unknown>;
  columns: string[];
  /** Renders one <tr>. `act` runs an RPC then reloads and re-counts. */
  row: (item: T, helpers: QueueHelpers) => React.ReactNode;
  title: string;
  sub?: string;
  emptyTitle: string;
  emptySub?: string;
  toolbar?: React.ReactNode;
  deps?: React.DependencyList;
}) {
  const toast = useToast();
  const ask = useAsk();
  const { refresh } = useBadges();

  const argsKey = JSON.stringify(rpcArgs ?? {});
  const load = useCallback(
    () => rpcList<T>(rpcName, rpcArgs ?? {}),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rpcName, argsKey],
  );

  const { data, error, loading, reload } = useAsync<T[]>(load, [argsKey, ...deps]);

  const helpers: QueueHelpers = {
    ask,
    toast,
    /** Run an action, report it, then refresh the list and the badges. */
    act: async (fn: () => Promise<unknown>, successMessage?: string) => {
      try {
        await fn();
        if (successMessage) toast.ok(successMessage);
        reload();
        refresh();
      } catch (e) {
        toast.err(e instanceof Error ? e.message : "Something went wrong.");
      }
    },
    reload: () => {
      reload();
      refresh();
    },
  };

  const rows = data ?? [];

  return (
    <div>
      <PageHead
        title={title}
        sub={sub}
        actions={
          <button className="btn ghost" onClick={reload} disabled={loading}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />

      {toolbar ? <div className="toolbar">{toolbar}</div> : null}

      {error ? <ErrorBox message={error} /> : null}

      {loading && !data ? (
        <TableSkeleton rows={4} cols={columns.length} />
      ) : !error && rows.length === 0 ? (
        <Empty title={emptyTitle} sub={emptySub} />
      ) : rows.length > 0 ? (
        <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1 }}>
          <table>
            <thead>
              <tr>
                {columns.map((c, i) => (
                  <th key={i}>{c}</th>
                ))}
              </tr>
            </thead>
            <tbody>{rows.map((item, i) => row(item, helpers))}</tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}

export type QueueHelpers = {
  ask: (options: AskOptions) => Promise<string | null>;
  toast: { ok: (t: string) => void; err: (t: string) => void; info: (t: string) => void };
  act: (fn: () => Promise<unknown>, successMessage?: string) => Promise<void>;
  reload: () => void;
};
