"use client";

import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton } from "@/components/ui";
import { safeUrl, fmtDay, truncate } from "@/lib/format";

type EventItem = {
  id: number;
  title: string;
  description: string | null;
  category: string | null;
  start_date: string | null;
  event_date: string | null;
  venue: string | null;
  city: string | null;
  location: string | null;
  cover_photo_url: string | null;
};

export default function EventsPage() {
  return (
    <Queue<EventItem>
      rpcName="admin_list_pending_events"
      title="Events"
      sub="Events members submitted. Approved events go live immediately and are featured on Home."
      columns={["Cover", "Event", ""]}
      emptyTitle="No events waiting"
      emptySub="Nothing has been submitted since you last looked."
      row={(e, { act, ask }) => (
        <tr key={e.id}>
          <td style={{ width: 116 }}>
            {/* Member-supplied URL — http(s) only. */}
            {safeUrl(e.cover_photo_url) ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                className="thumb"
                src={safeUrl(e.cover_photo_url)!}
                alt=""
                loading="lazy"
              />
            ) : (
              <div className="thumb" />
            )}
          </td>
          <td>
            <b>{e.title}</b>
            <div className="meta">
              {[
                e.category,
                fmtDay(e.start_date ?? e.event_date),
                [e.venue, e.city].filter(Boolean).join(", ") || e.location,
              ]
                .filter(Boolean)
                .join(" · ")}
            </div>
            {e.description ? (
              <div className="meta">{truncate(e.description, 300)}</div>
            ) : null}
          </td>
          <td className="nowrap">
            <div className="actions">
              <BusyButton
                className="btn green sm"
                onClick={() =>
                  act(() => rpc("admin_approve_event", { p_id: e.id }), "Event is live.")
                }
              >
                Approve
              </BusyButton>
              <BusyButton
                className="btn red sm"
                onClick={async () => {
                  const ok = await ask({
                    title: "Reject event",
                    sub: `“${e.title}” will not be published.`,
                    confirmLabel: "Reject",
                    tone: "red",
                  });
                  if (ok === null) return;
                  await act(
                    () => rpc("admin_reject_event", { p_id: e.id }),
                    "Event rejected.",
                  );
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
