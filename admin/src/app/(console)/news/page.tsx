"use client";

import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton } from "@/components/ui";
import { safeUrl, fmtAgo, truncate } from "@/lib/format";

type NewsItem = {
  id: number;
  title: string;
  summary: string | null;
  body: string | null;
  category: string | null;
  author_name: string;
  cover_photo_url: string | null;
  created_at: string;
};

export default function NewsPage() {
  return (
    <Queue<NewsItem>
      rpcName="admin_list_pending_news"
      title="Advent News"
      sub="Stories members submitted. Approving publishes it to everyone."
      columns={["Cover", "Story", ""]}
      emptyTitle="No stories waiting"
      emptySub="Nothing has been submitted since you last looked."
      row={(n, { act, ask }) => (
        <tr key={n.id}>
          <td style={{ width: 116 }}>
            {/* Member-supplied URL — http(s) only. */}
            {safeUrl(n.cover_photo_url) ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                className="thumb"
                src={safeUrl(n.cover_photo_url)!}
                alt=""
                loading="lazy"
              />
            ) : (
              <div className="thumb" />
            )}
          </td>
          <td>
            <b>{n.title}</b>
            <div className="meta">
              {[n.category, `by ${n.author_name}`, fmtAgo(n.created_at)]
                .filter(Boolean)
                .join(" · ")}
            </div>
            {n.summary ? <div className="meta">{n.summary}</div> : null}
            {n.body ? (
              <div className="meta" style={{ marginTop: 4 }}>
                {truncate(n.body, 400)}
              </div>
            ) : null}
          </td>
          <td className="nowrap">
            <div className="actions">
              <BusyButton
                className="btn green sm"
                onClick={() =>
                  act(() => rpc("admin_approve_news", { p_id: n.id }), "Story published.")
                }
              >
                Approve
              </BusyButton>
              <BusyButton
                className="btn red sm"
                onClick={async () => {
                  const reason = await ask({
                    title: "Reject story",
                    sub: `${n.author_name} will be told. A reason lets them fix it and resubmit.`,
                    input: { placeholder: "Reason (optional)" },
                    confirmLabel: "Reject",
                    tone: "red",
                  });
                  if (reason === null) return;
                  await act(
                    () => rpc("admin_reject_news", { p_id: n.id, p_reason: reason }),
                    "Story rejected.",
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
