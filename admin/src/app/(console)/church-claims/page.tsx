"use client";

import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton } from "@/components/ui";
import { IconWhatsApp } from "@/components/icons";
import { fmtAgo, openWhatsApp, truncate, waNumber } from "@/lib/format";
import { useSession } from "@/lib/session";

type Claim = {
  id: number;
  church_name: string | null;
  church_city: string | null;
  applicant_name: string | null;
  applicant_phone: string | null;
  applicant_email: string | null;
  role: string | null;
  note: string | null;
  created_at: string;
};

/**
 * The two WhatsApp messages this queue sends. Kept verbatim from the console
 * that is being replaced — the founder has been sending exactly these, and a
 * "nicer" rewrite would change the voice applicants already know.
 */
function approvedMessage(name: string, church: string): string {
  return (
    `Hi ${name || "there"}, you are now an approved admin for ${church || "your church"} on Adventist Super App! 🎉\n\n` +
    `In your church dashboard you can:\n` +
    `• Post announcements to your members\n` +
    `• Share church updates to the whole app (shown with your church name + verified tick)\n` +
    `• Post church events — they go live instantly and are featured on Home\n` +
    `• See your members by name and how many follow your church\n` +
    `• Invite members via WhatsApp\n` +
    `• Manage your church info, logo and cover photo\n\n` +
    `Open the app → Settings → your church dashboard. God bless!`
  );
}

function proofMessage(name: string, church: string): string {
  return (
    `Hi ${name || "there"}, thank you for requesting to manage ${church || "your church"} on Adventist Super App. ` +
    `Before we can approve you, please send proof of your position at the church (e.g. Elder, Clerk, Pastor) — ` +
    `a photo of an appointment letter or your church ID. Reply here with it and we will review again. Thank you!`
  );
}

export default function ChurchClaimsPage() {
  // Moderators do not see contact details — that is the whole point of the
  // role. The queue still works for them; they simply approve on the note.
  const { can } = useSession();
  const seesPii = can("manager");

  return (
    <Queue<Claim>
      rpcName="admin_list_pending_church_admins"
      title="Church claims"
      sub="Members asking to manage a church. Approving grants posting rights to that church only."
      columns={["Church", "Applicant", ""]}
      emptyTitle="No claims waiting"
      emptySub="Nobody is asking to manage a church right now."
      row={(c, { act, ask }) => {
        const wa = waNumber(c.applicant_phone);
        const name = c.applicant_name ?? "";
        const church = c.church_name ?? "";
        return (
          <tr key={c.id}>
            <td>
              <b>{church || "Church"}</b>
              <div className="meta">{c.church_city ?? "—"}</div>
            </td>
            <td>
              <b>{name || "—"}</b>
              <div className="meta">
                {[c.role ?? "admin", fmtAgo(c.created_at)].join(" · ")}
              </div>
              {seesPii ? (
                <div className="meta">
                  {c.applicant_phone ?? "—"} · {c.applicant_email ?? "—"}
                </div>
              ) : (
                <div className="faint">Contact details hidden at your role</div>
              )}
              {c.note ? (
                <div className="meta" style={{ marginTop: 4 }}>
                  “{truncate(c.note, 300)}”
                </div>
              ) : null}
            </td>
            <td className="nowrap">
              <div className="actions">
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
                  className="btn green sm"
                  onClick={() =>
                    act(async () => {
                      await rpc("admin_approve_church_admin", { p_id: c.id });
                      // Opened after the approval succeeded, never before —
                      // a popup congratulating someone on an approval that
                      // then failed is worse than no message.
                      if (seesPii) openWhatsApp(c.applicant_phone, approvedMessage(name, church));
                    }, `${name || "Applicant"} can now post as ${church || "their church"}.`)
                  }
                >
                  Approve
                </BusyButton>
                <BusyButton
                  className="btn red sm"
                  onClick={async () => {
                    const reason = await ask({
                      title: "Reject or ask for proof",
                      sub: seesPii
                        ? "We will open WhatsApp with a request for proof of position."
                        : "The applicant is told, with your reason.",
                      input: { placeholder: "Reason (optional)" },
                      confirmLabel: "Reject",
                      tone: "red",
                    });
                    if (reason === null) return;
                    await act(async () => {
                      await rpc("admin_reject_church_admin", {
                        p_id: c.id,
                        p_reason: reason,
                      });
                      if (seesPii) openWhatsApp(c.applicant_phone, proofMessage(name, church));
                    }, "Claim rejected.");
                  }}
                >
                  Reject
                </BusyButton>
              </div>
            </td>
          </tr>
        );
      }}
      deps={[seesPii]}
    />
  );
}
