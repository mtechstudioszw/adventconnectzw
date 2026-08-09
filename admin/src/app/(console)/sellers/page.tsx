"use client";

import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton, StatusChip } from "@/components/ui";
import { IconWhatsApp } from "@/components/icons";
import { waNumber } from "@/lib/format";

type Seller = {
  id: number;
  business_name: string;
  category: string | null;
  city: string | null;
  province: string | null;
  description: string | null;
  phone: string | null;
  whatsapp: string | null;
  status: string;
  application_attempts: number;
};

export default function SellersPage() {
  return (
    <Queue<Seller>
      rpcName="admin_pending_sellers"
      title="Sellers"
      sub="Approve a storefront and it appears on the marketplace. Reject it and the applicant is told why."
      columns={["Business", "Contact", "Status", ""]}
      emptyTitle="No sellers waiting"
      emptySub="Every application has been dealt with."
      row={(s, { act, ask }) => {
        const wa = waNumber(s.whatsapp ?? s.phone);
        return (
          <tr key={s.id}>
            <td>
              <b>{s.business_name}</b>
              <div className="meta">
                {[s.category, s.city, s.province].filter(Boolean).join(" · ") || "—"}
              </div>
              {s.description ? <div className="meta">{s.description}</div> : null}
            </td>
            <td>
              {s.phone ?? "—"}
              {s.whatsapp ? <div className="meta">WhatsApp {s.whatsapp}</div> : null}
            </td>
            <td>
              {/* A third attempt is the last one the applicant gets, so it is
                  flagged rather than shown as one more pending row. */}
              {s.status === "final_review_pending" ? (
                <span className="chip red">FINAL #{s.application_attempts}/3</span>
              ) : (
                <StatusChip status={s.status} />
              )}
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
                      () => rpc("admin_approve_seller", { p_seller_id: s.id }),
                      `${s.business_name} is live on the marketplace.`,
                    )
                  }
                >
                  Approve
                </BusyButton>
                <BusyButton
                  className="btn red sm"
                  onClick={async () => {
                    const reason = await ask({
                      title: "Reject seller",
                      sub: `${s.business_name} will be told. A reason helps them fix it and re-apply.`,
                      input: { placeholder: "Reason (optional)" },
                      confirmLabel: "Reject",
                      tone: "red",
                    });
                    if (reason === null) return;
                    await act(
                      () =>
                        rpc("admin_reject_seller", {
                          p_seller_id: s.id,
                          p_reason: reason,
                        }),
                      "Seller rejected.",
                    );
                  }}
                >
                  Reject
                </BusyButton>
              </div>
            </td>
          </tr>
        );
      }}
    />
  );
}
