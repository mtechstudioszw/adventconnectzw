"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { supabase } from "@/lib/supabase";
import { Queue } from "@/components/Queue";
import { BusyButton, Note, Segmented, StatusChip } from "@/components/ui";
import { fmtDay } from "@/lib/format";

/**
 * Gold tick ID checks (patch_314). Super admin only — these rows point at
 * people's ID documents and selfies, so the database refuses everyone else
 * regardless of their console role.
 *
 * The tick itself only shows while the member is ALSO paying (Premium or the
 * $1 Verified plan) — refresh_paid_perks decides that, not this screen. An
 * approval for someone who is not paying is remembered and the tick appears
 * the day they subscribe.
 */
type Request = {
  id: string;
  user_id: string;
  member_name: string | null;
  legal_name: string | null;
  kind: string;
  category: string | null;
  status: string;
  reason: string | null;
  created_at: string;
  reviewed_at: string | null;
  id_doc_path: string | null;
  selfie_path: string | null;
  paying: boolean;
  plan: string;
};

const FILTERS = ["pending", "approved", "rejected", "revoked", "all"] as const;
type Filter = (typeof FILTERS)[number];

const BUCKET = "verification_docs";

async function openDoc(path: string | null) {
  if (!path) return;
  const { data, error } = await supabase()
    .storage.from(BUCKET)
    .createSignedUrl(path, 300);
  if (error || !data?.signedUrl) {
    throw new Error("Could not open that document. It may already have been deleted.");
  }
  window.open(data.signedUrl, "_blank", "noopener,noreferrer");
}

/** The documents are only needed for the decision — delete them after it. */
async function deleteDocs(r: Request) {
  const paths = [r.id_doc_path, r.selfie_path].filter((p): p is string => !!p);
  if (paths.length === 0) return;
  await supabase().storage.from(BUCKET).remove(paths);
}

export default function VerificationPage() {
  const [filter, setFilter] = useState<Filter>("pending");

  return (
    <div>
      <Note>
        Only a <b>super admin</b> can see this page — it shows people&apos;s ID
        documents. Documents open for 5 minutes and are deleted once you decide.
        The gold tick appears only while the member is also on <b>Premium</b> or
        the <b>$1 Verified plan</b>.
      </Note>
      <Queue<Request>
        rpcName="admin_list_verifications"
        rpcArgs={{ p_status: filter }}
        title="Gold tick checks"
        sub="Approve a member's identity so their gold tick can show."
        columns={["Member", "Plan", "Status", ""]}
        emptyTitle={filter === "pending" ? "No ID checks waiting" : "Nothing here"}
        emptySub="New requests appear when a member applies for the gold tick."
        toolbar={
          <Segmented
            options={FILTERS}
            value={filter}
            onChange={setFilter}
            labels={{ pending: "Waiting", approved: "Approved", rejected: "Rejected", revoked: "Revoked", all: "All" }}
          />
        }
        deps={[filter]}
        row={(r, { act, ask, toast }) => (
          <tr key={r.id}>
            <td>
              <b>{r.member_name ?? "Member"}</b>
              <div className="meta">
                {[
                  r.legal_name ? `Legal name: ${r.legal_name}` : null,
                  r.kind === "page" ? "Organization Page" : "Person",
                  r.category,
                  `Applied ${fmtDay(r.created_at)}`,
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </div>
              {r.reason ? <div className="meta">Reason given: {r.reason}</div> : null}
            </td>
            <td>
              <span className={`chip ${r.paying ? "green" : "grey"}`}>{r.plan.toUpperCase()}</span>
            </td>
            <td>
              <StatusChip status={r.status} />
            </td>
            <td className="nowrap">
              <div className="actions">
                {r.id_doc_path ? (
                  <BusyButton
                    className="btn ghost sm"
                    onClick={async () => {
                      try {
                        await openDoc(r.id_doc_path);
                      } catch (e) {
                        toast.err(e instanceof Error ? e.message : "Could not open it.");
                      }
                    }}
                  >
                    ID
                  </BusyButton>
                ) : null}
                {r.selfie_path ? (
                  <BusyButton
                    className="btn ghost sm"
                    onClick={async () => {
                      try {
                        await openDoc(r.selfie_path);
                      } catch (e) {
                        toast.err(e instanceof Error ? e.message : "Could not open it.");
                      }
                    }}
                  >
                    Selfie
                  </BusyButton>
                ) : null}

                {r.status === "pending" ? (
                  <>
                    <BusyButton
                      className="btn green sm"
                      onClick={async () => {
                        const ok = await ask({
                          title: `Approve ${r.member_name ?? "this member"}?`,
                          sub: r.paying
                            ? "Their gold tick appears now. The documents are then deleted."
                            : "They are not paying yet, so the tick appears when they subscribe. The documents are then deleted.",
                          confirmLabel: "Approve",
                        });
                        if (ok === null) return;
                        await act(async () => {
                          await rpc("admin_review_verification", {
                            p_id: r.id,
                            p_action: "approve",
                            p_reason: null,
                          });
                          await deleteDocs(r);
                        }, "Approved.");
                      }}
                    >
                      Approve
                    </BusyButton>
                    <BusyButton
                      className="btn red sm"
                      onClick={async () => {
                        const reason = await ask({
                          title: "Reject this ID check",
                          sub: "The member sees this reason. Be kind and specific, e.g. “The photo is blurry — please try again in good light.”",
                          input: { placeholder: "Reason…", multiline: true, required: true },
                          confirmLabel: "Reject",
                          tone: "red",
                        });
                        if (!reason) return;
                        await act(async () => {
                          await rpc("admin_review_verification", {
                            p_id: r.id,
                            p_action: "reject",
                            p_reason: reason,
                          });
                          await deleteDocs(r);
                        }, "Rejected — they were told why.");
                      }}
                    >
                      Reject
                    </BusyButton>
                  </>
                ) : null}

                {r.status === "approved" ? (
                  <BusyButton
                    className="btn red sm"
                    onClick={async () => {
                      const reason = await ask({
                        title: "Revoke the gold tick",
                        sub: "Their tick disappears at once. The member sees this reason.",
                        input: { placeholder: "Reason…", multiline: true, required: true },
                        confirmLabel: "Revoke",
                        tone: "red",
                      });
                      if (!reason) return;
                      await act(
                        () =>
                          rpc("admin_review_verification", {
                            p_id: r.id,
                            p_action: "revoke",
                            p_reason: reason,
                          }),
                        "Tick revoked.",
                      );
                    }}
                  >
                    Revoke
                  </BusyButton>
                ) : null}
              </div>
            </td>
          </tr>
        )}
      />
    </div>
  );
}
