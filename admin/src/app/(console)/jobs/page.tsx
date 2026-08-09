"use client";

import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton } from "@/components/ui";
import { truncate } from "@/lib/format";

type JobItem = {
  id: number;
  title: string;
  company: string | null;
  job_type: string | null;
  category: string | null;
  location: string | null;
  description: string | null;
};

export default function JobsPage() {
  return (
    <Queue<JobItem>
      rpcName="admin_list_pending_jobs"
      title="Jobs"
      sub="Jobs members submitted. Approving publishes the listing."
      columns={["Job", ""]}
      emptyTitle="No jobs waiting"
      emptySub="Nothing has been submitted since you last looked."
      row={(j, { act, ask }) => (
        <tr key={j.id}>
          <td>
            <b>{j.title}</b>
            <div className="meta">
              {[j.company, j.job_type, j.category, j.location].filter(Boolean).join(" · ")}
            </div>
            {j.description ? (
              <div className="meta">{truncate(j.description, 300)}</div>
            ) : null}
          </td>
          <td className="nowrap">
            <div className="actions">
              <BusyButton
                className="btn green sm"
                onClick={() =>
                  act(() => rpc("admin_approve_job", { p_id: j.id }), "Job is live.")
                }
              >
                Approve
              </BusyButton>
              <BusyButton
                className="btn red sm"
                onClick={async () => {
                  const ok = await ask({
                    title: "Reject job",
                    sub: `“${j.title}” will not be published.`,
                    confirmLabel: "Reject",
                    tone: "red",
                  });
                  if (ok === null) return;
                  await act(() => rpc("admin_reject_job", { p_id: j.id }), "Job rejected.");
                }}
              >
                Reject
              </BusyButton>
            </div>
          </td>
        </tr>
      )}
    />
  );
}
