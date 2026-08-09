"use client";

import { useCallback, useState } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import {
  BusyButton,
  Empty,
  ErrorBox,
  PageHead,
  TableSkeleton,
} from "@/components/ui";
import { IconRefresh, IconWhatsApp } from "@/components/icons";
import { safeUrl, waNumber } from "@/lib/format";

type Submission = {
  id: number;
  link: string;
  note: string | null;
  submitter_name: string | null;
  submitter_contact: string | null;
  profile_name: string | null;
  profile_email: string | null;
};

type Channel = {
  channel_id: string;
  title: string | null;
  handle: string | null;
  status: string;
  is_live: boolean;
  backfill_done: boolean;
};

export default function WatchPage() {
  const toast = useToast();
  const ask = useAsk();
  const [link, setLink] = useState("");
  const [adding, setAdding] = useState(false);

  const load = useCallback(
    () =>
      Promise.all([
        rpcList<Submission>("admin_list_youtube_submissions", { p_status: "pending" }),
        rpcList<Channel>("admin_list_youtube_channels", { p_status: "all" }),
      ]),
    [],
  );

  const { data, error, loading, reload } = useAsync(load, []);
  const [subs, channels] = data ?? [[], []];

  const addChannel = async () => {
    const value = link.trim();
    if (!value) return;
    setAdding(true);
    try {
      await rpc("admin_add_youtube_channel", { p_link: value });
      setLink("");
      toast.ok("Added — it will resolve and start syncing shortly.");
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Could not add that channel.");
    } finally {
      setAdding(false);
    }
  };

  const act = async (fn: () => Promise<unknown>, message: string) => {
    try {
      await fn();
      toast.ok(message);
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Something went wrong.");
    }
  };

  return (
    <div className="stack">
      <PageHead
        title="Watch channels"
        sub="What feeds the Watch tab — creator submissions, and the channels already syncing."
        actions={
          <button className="btn ghost" onClick={reload} disabled={loading}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />

      {error ? <ErrorBox message={error} /> : null}

      <div className="card card-pad">
        <div className="section-title">Add a channel</div>
        <form
          className="row"
          style={{ gap: 8, flexWrap: "wrap" }}
          onSubmit={(e) => {
            e.preventDefault();
            void addChannel();
          }}
        >
          <input
            className="input"
            style={{ maxWidth: 420 }}
            placeholder="YouTube channel link or @handle"
            value={link}
            onChange={(e) => setLink(e.target.value)}
          />
          <button className="btn primary" type="submit" disabled={adding || !link.trim()}>
            {adding ? <span className="spinner" /> : null}
            Add
          </button>
        </form>
      </div>

      <section>
        <div className="section-title">
          Pending submissions
          {subs.length > 0 ? <span className="count">{subs.length}</span> : null}
        </div>
        {loading && !data ? (
          <TableSkeleton rows={2} cols={3} />
        ) : subs.length === 0 ? (
          <Empty title="No submissions waiting" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Channel</th>
                  <th>Submitted by</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {subs.map((s) => {
                  const wa = waNumber(s.submitter_contact);
                  // Member-submitted. Only http(s) becomes a link; anything
                  // else is shown as inert text so it can still be read and
                  // judged, but cannot be clicked into.
                  const link = safeUrl(s.link);
                  return (
                    <tr key={s.id}>
                      <td>
                        {link ? (
                          <a
                            href={link}
                            target="_blank"
                            rel="noopener noreferrer"
                            style={{ color: "var(--blue)", fontWeight: 600 }}
                          >
                            {s.link}
                          </a>
                        ) : (
                          <>
                            <span className="mono">{s.link}</span>
                            <div className="meta" style={{ color: "var(--red)" }}>
                              Not a valid web link — do not open it.
                            </div>
                          </>
                        )}
                        {s.note ? <div className="meta">“{s.note}”</div> : null}
                      </td>
                      <td>
                        {s.submitter_name ?? s.profile_name ?? "—"}
                        <div className="meta">
                          {s.submitter_contact ?? s.profile_email ?? ""}
                        </div>
                      </td>
                      <td className="nowrap">
                        <div className="actions">
                          {wa ? (
                            <a
                              className="btn ghost sm"
                              href={`https://wa.me/${wa}`}
                              target="_blank"
                              rel="noopener noreferrer"
                            >
                              <IconWhatsApp size={14} />
                            </a>
                          ) : null}
                          <BusyButton
                            className="btn green sm"
                            onClick={() =>
                              act(
                                () =>
                                  rpc("admin_review_youtube_submission", {
                                    p_id: s.id,
                                    p_approve: true,
                                  }),
                                "Channel approved — syncing starts shortly.",
                              )
                            }
                          >
                            Approve
                          </BusyButton>
                          <BusyButton
                            className="btn red sm"
                            onClick={async () => {
                              const reason = await ask({
                                title: "Reject submission",
                                sub: "Optional reason, sent to whoever submitted it.",
                                input: { placeholder: "Reason (optional)" },
                                confirmLabel: "Reject",
                                tone: "red",
                              });
                              if (reason === null) return;
                              await act(
                                () =>
                                  rpc("admin_review_youtube_submission", {
                                    p_id: s.id,
                                    p_approve: false,
                                    p_reason: reason,
                                  }),
                                "Submission rejected.",
                              );
                            }}
                          >
                            Reject
                          </BusyButton>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section>
        <div className="section-title">
          Channels
          {channels.length > 0 ? <span className="count">{channels.length}</span> : null}
        </div>
        {loading && !data ? (
          <TableSkeleton rows={3} cols={3} />
        ) : channels.length === 0 ? (
          <Empty title="No channels yet" sub="Add one above to start filling the Watch tab." />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Channel</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {channels.map((c) => (
                  <tr key={c.channel_id}>
                    <td>
                      <b>{c.title ?? c.channel_id}</b>
                      {c.handle ? <div className="meta">{c.handle}</div> : null}
                    </td>
                    <td>
                      <span className={`chip ${c.status === "active" ? "green" : "grey"}`}>
                        {c.status.toUpperCase()}
                      </span>
                      {c.is_live ? <span className="chip red"> LIVE</span> : null}
                      {c.status === "active" && !c.backfill_done ? (
                        <div className="meta">syncing…</div>
                      ) : null}
                    </td>
                    <td className="nowrap">
                      {c.status === "active" ? (
                        <BusyButton
                          className="btn ghost sm"
                          onClick={async () => {
                            const ok = await ask({
                              title: "Disable channel",
                              sub: `Hides ${c.title ?? "this channel"}'s videos from Watch and stops syncing it.`,
                              confirmLabel: "Disable",
                              tone: "red",
                            });
                            if (ok === null) return;
                            await act(
                              () =>
                                rpc("admin_set_youtube_channel_status", {
                                  p_channel_id: c.channel_id,
                                  p_status: "disabled",
                                }),
                              "Channel disabled.",
                            );
                          }}
                        >
                          Disable
                        </BusyButton>
                      ) : (
                        <BusyButton
                          className="btn green sm"
                          onClick={() =>
                            act(
                              () =>
                                rpc("admin_set_youtube_channel_status", {
                                  p_channel_id: c.channel_id,
                                  p_status: "active",
                                }),
                              "Channel enabled.",
                            )
                          }
                        >
                          Enable
                        </BusyButton>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
