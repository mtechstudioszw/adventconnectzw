"use client";

import { useCallback } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import { BusyButton, Empty, ErrorBox, PageHead, StatusChip, TableSkeleton } from "@/components/ui";
import { fmtDay } from "@/lib/format";
import { IconRefresh } from "@/components/icons";

/**
 * The fundraiser: campaigns (admin_fundraiser_overview) and the pledges
 * members reported paying outside the stores, waiting to be checked against
 * the bank / EcoCash statement (fundraiser_list_pending). Confirming counts the
 * money toward the goal; both decisions are audited (patch_315). Owner + super
 * admin — this is money.
 */
type Campaign = {
  campaign_key: string;
  title: string;
  status: string;
  goal_cents: number;
  raised_cents: number;
  pending_cents: number;
  pending_count: number;
  supporters: number;
  currency: string;
  created_at: string;
  completed_at: string | null;
};

type Pending = {
  id: number;
  user_id: string;
  full_name: string | null;
  amount_cents: number;
  method: string | null;
  reference: string | null;
  created_at: string;
};

const money = (cents: number, cur = "USD") =>
  `${cur === "USD" ? "$" : cur + " "}${(cents / 100).toFixed(2)}`;

export default function FundraiserPage() {
  const toast = useToast();
  const ask = useAsk();

  const loadCampaigns = useCallback(() => rpcList<Campaign>("admin_fundraiser_overview"), []);
  const loadPending = useCallback(() => rpcList<Pending>("fundraiser_list_pending"), []);
  const campaigns = useAsync<Campaign[]>(loadCampaigns, []);
  const pending = useAsync<Pending[]>(loadPending, []);

  const reload = () => {
    campaigns.reload();
    pending.reload();
  };

  const run = async (fn: () => Promise<unknown>, msg: string) => {
    try {
      await fn();
      toast.ok(msg);
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Something went wrong.");
    }
  };

  return (
    <div>
      <PageHead
        title="Fundraiser"
        sub="Campaigns, and pledges waiting to be checked against your statement."
        actions={
          <button className="btn ghost" onClick={reload}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />

      <h3 style={{ fontSize: 15, fontWeight: 700, margin: "4px 0 8px" }}>Waiting to confirm</h3>
      {pending.error ? <ErrorBox message={pending.error} /> : null}
      {pending.loading && !pending.data ? (
        <TableSkeleton rows={3} cols={3} />
      ) : (pending.data ?? []).length === 0 ? (
        <Empty title="Nothing to confirm" sub="Pledges appear here when a member says they paid." />
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Member</th>
                <th>Pledge</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {(pending.data ?? []).map((p) => (
                <tr key={p.id}>
                  <td>
                    <b>{p.full_name ?? "Member"}</b>
                    <div className="meta">{fmtDay(p.created_at)}</div>
                  </td>
                  <td>
                    <b>{money(p.amount_cents)}</b>
                    <div className="meta">
                      {[p.method, p.reference ? `Ref: ${p.reference}` : null].filter(Boolean).join(" · ")}
                    </div>
                  </td>
                  <td className="nowrap">
                    <div className="actions">
                      <BusyButton
                        className="btn green sm"
                        onClick={async () => {
                          const amount = await ask({
                            title: "Confirm the amount received",
                            sub: "Check your statement. Enter what actually arrived, in dollars.",
                            input: { placeholder: (p.amount_cents / 100).toFixed(2), required: true },
                            confirmLabel: "Confirm",
                          });
                          if (!amount) return;
                          const cents = Math.round(Number(amount.replace(/[^0-9.]/g, "")) * 100);
                          if (!cents || cents < 0) {
                            toast.err("Enter an amount like 5 or 2.50.");
                            return;
                          }
                          await run(
                            () => rpc("admin_confirm_contribution", { p_id: p.id, p_amount_cents: cents }),
                            "Confirmed — counted toward the goal.",
                          );
                        }}
                      >
                        Confirm
                      </BusyButton>
                      <BusyButton
                        className="btn red sm"
                        onClick={async () => {
                          const note = await ask({
                            title: "Reject this pledge",
                            sub: "Nothing arrived, or it does not match. The member sees this note.",
                            input: { placeholder: "Note…", multiline: true, required: true },
                            confirmLabel: "Reject",
                            tone: "red",
                          });
                          if (!note) return;
                          await run(
                            () => rpc("admin_reject_contribution", { p_id: p.id, p_note: note }),
                            "Rejected.",
                          );
                        }}
                      >
                        Reject
                      </BusyButton>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h3 style={{ fontSize: 15, fontWeight: 700, margin: "22px 0 8px" }}>Campaigns</h3>
      {campaigns.error ? <ErrorBox message={campaigns.error} /> : null}
      {campaigns.loading && !campaigns.data ? (
        <TableSkeleton rows={2} cols={4} />
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Campaign</th>
                <th>Raised</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {(campaigns.data ?? []).map((c) => {
                const pct = c.goal_cents ? Math.min(100, Math.round((c.raised_cents / c.goal_cents) * 100)) : 0;
                return (
                  <tr key={c.campaign_key}>
                    <td>
                      <b>{c.title}</b>
                      <div className="meta">
                        {c.campaign_key} · started {fmtDay(c.created_at)}
                      </div>
                    </td>
                    <td>
                      <b>{money(c.raised_cents, c.currency)}</b> of {money(c.goal_cents, c.currency)} ({pct}%)
                      <div className="meta">
                        {c.supporters} supporters · {c.pending_count} pending ({money(c.pending_cents, c.currency)})
                      </div>
                    </td>
                    <td>
                      <StatusChip status={c.status} />
                    </td>
                    <td className="nowrap">
                      <div className="actions">
                        {c.status !== "active" ? (
                          <BusyButton
                            className="btn ghost sm"
                            onClick={() =>
                              run(
                                () => rpc("admin_set_fundraiser_status", { p_key: c.campaign_key, p_status: "active" }),
                                "Campaign is live in the app.",
                              )
                            }
                          >
                            Make live
                          </BusyButton>
                        ) : (
                          <BusyButton
                            className="btn ghost sm"
                            onClick={() =>
                              run(
                                () => rpc("admin_set_fundraiser_status", { p_key: c.campaign_key, p_status: "paused" }),
                                "Campaign paused.",
                              )
                            }
                          >
                            Pause
                          </BusyButton>
                        )}
                        {c.status !== "completed" ? (
                          <BusyButton
                            className="btn ghost sm"
                            onClick={async () => {
                              const ok = await ask({
                                title: `Mark “${c.title}” complete?`,
                                sub: "Members see a thank-you instead of the appeal.",
                                confirmLabel: "Complete",
                              });
                              if (ok === null) return;
                              await run(
                                () =>
                                  rpc("admin_set_fundraiser_status", { p_key: c.campaign_key, p_status: "completed" }),
                                "Campaign completed.",
                              );
                            }}
                          >
                            Complete
                          </BusyButton>
                        ) : null}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
