"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton, Segmented } from "@/components/ui";
import { IconWhatsApp } from "@/components/icons";
import { fmtDay, waNumber } from "@/lib/format";
import { useSession } from "@/lib/session";

type ChurchAdmin = {
  id: number;
  church_name: string | null;
  church_city: string | null;
  follower_count: number;
  profile_name: string | null;
  applicant_name: string | null;
  profile_email: string | null;
  applicant_email: string | null;
  applicant_phone: string | null;
  role: string | null;
  status: string;
  approved_at: string | null;
  created_at: string;
  rejection_reason: string | null;
};

const FILTERS = ["approved", "revoked", "all"] as const;

export default function ChurchAdminsPage() {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("approved");
  const [query, setQuery] = useState("");
  const [applied, setApplied] = useState("");
  const { can } = useSession();
  const seesPii = can("manager");

  return (
    <Queue<ChurchAdmin>
      rpcName="admin_list_church_admins"
      rpcArgs={{ p_status: filter, p_search: applied }}
      title="Church admins"
      sub="Everyone already approved to post as a church. Removing one is sticky — they cannot re-claim that church."
      columns={["Church", "Admin", "Status", ""]}
      emptyTitle="No church admins"
      emptySub={applied ? "Nothing matched that search." : undefined}
      toolbar={
        <>
          <Segmented options={FILTERS} value={filter} onChange={setFilter} />
          <form
            className="row"
            style={{ gap: 8 }}
            onSubmit={(e) => {
              e.preventDefault();
              setApplied(query.trim());
            }}
          >
            <input
              className="input"
              style={{ maxWidth: 260 }}
              placeholder="Search church, name or email…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
            <button className="btn primary" type="submit">
              Search
            </button>
          </form>
        </>
      }
      row={(a, { act, ask }) => {
        const removed = a.status === "revoked";
        const wa = waNumber(a.applicant_phone);
        const name = a.profile_name ?? a.applicant_name ?? "—";
        return (
          <tr key={a.id}>
            <td>
              <b>{a.church_name ?? "Church"}</b>
              <div className="meta">
                {[a.church_city, `${a.follower_count} member(s)`].filter(Boolean).join(" · ")}
              </div>
            </td>
            <td>
              <b>{name}</b>
              {seesPii ? (
                <>
                  <div className="meta">{a.profile_email ?? a.applicant_email ?? "—"}</div>
                  <div className="meta">
                    {[a.applicant_phone, a.role, `since ${fmtDay(a.approved_at ?? a.created_at)}`]
                      .filter(Boolean)
                      .join(" · ")}
                  </div>
                </>
              ) : (
                <div className="meta">
                  {[a.role, `since ${fmtDay(a.approved_at ?? a.created_at)}`]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
              )}
              {removed && a.rejection_reason ? (
                <div className="meta">↳ removed: {a.rejection_reason}</div>
              ) : null}
            </td>
            <td>
              <span className={`chip ${removed ? "red" : "green"}`}>
                {removed ? "REMOVED" : "ACTIVE"}
              </span>
            </td>
            <td className="nowrap">
              <div className="actions">
                {removed ? (
                  <BusyButton
                    className="btn green sm"
                    onClick={async () => {
                      const ok = await ask({
                        title: "Re-instate admin",
                        sub: `Restores ${name}'s posting rights for ${a.church_name ?? "this church"}.`,
                        confirmLabel: "Re-instate",
                        tone: "green",
                      });
                      if (ok === null) return;
                      await act(
                        () => rpc("admin_approve_church_admin", { p_id: a.id }),
                        "Access restored.",
                      );
                    }}
                  >
                    Re-instate
                  </BusyButton>
                ) : (
                  <>
                    {wa && seesPii ? (
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
                      className="btn ghost sm"
                      onClick={async () => {
                        const msg = await ask({
                          title: `Warn ${name}`,
                          sub: "Sent as an in-app notification and a push.",
                          input: { placeholder: "Write the warning…", multiline: true, required: true },
                          confirmLabel: "Send warning",
                        });
                        if (!msg) return;
                        await act(
                          () => rpc("admin_warn_church_admin", { p_id: a.id, p_message: msg }),
                          "Warning sent.",
                        );
                      }}
                    >
                      Warn
                    </BusyButton>
                    <BusyButton
                      className="btn red sm"
                      onClick={async () => {
                        const reason = await ask({
                          title: "Remove church admin",
                          sub: `${name} loses every posting right for ${a.church_name ?? "this church"} and cannot re-claim it. Only an owner can undo this.`,
                          input: { placeholder: "Reason (sent to them)" },
                          confirmLabel: "Remove",
                          tone: "red",
                        });
                        if (reason === null) return;
                        await act(
                          () =>
                            rpc("admin_revoke_church_admin", {
                              p_id: a.id,
                              p_reason: reason,
                            }),
                          "Access removed.",
                        );
                      }}
                    >
                      Remove
                    </BusyButton>
                  </>
                )}
              </div>
            </td>
          </tr>
        );
      }}
      deps={[seesPii]}
    />
  );
}
