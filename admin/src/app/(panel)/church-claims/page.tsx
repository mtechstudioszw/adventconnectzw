import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import {
  approveChurchClaimAction,
  rejectChurchClaimAction,
} from "./actions";
import Link from "next/link";

type Filter = "pending" | "approved" | "rejected" | "all";

type ClaimRow = {
  id: number;
  user_id: string;
  church_id: number;
  role: string;
  status: "pending" | "approved" | "rejected";
  applicant_name: string | null;
  applicant_phone: string | null;
  applicant_email: string | null;
  applicant_note: string | null;
  rejection_reason: string | null;
  created_at: string;
  churches: { name: string | null; city: string | null } | null;
};

async function fetchClaims(filter: Filter): Promise<ClaimRow[]> {
  const supabase = getServiceSupabase();
  let query = supabase
    .from("church_admins")
    .select(
      "id, user_id, church_id, role, status, applicant_name, applicant_phone, applicant_email, applicant_note, rejection_reason, created_at, churches!church_admins_church_id_fkey(name, city)",
    )
    .order("created_at", { ascending: false })
    .limit(200);
  if (filter !== "all") {
    query = query.eq("status", filter);
  }
  const { data, error } = await query;
  if (error) {
    throw new Error(error.message);
  }
  return (data ?? []) as unknown as ClaimRow[];
}

export default async function ChurchClaimsPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  await requireAdmin();
  const filter: Filter =
    searchParams.status === "all" ||
    searchParams.status === "approved" ||
    searchParams.status === "rejected"
      ? (searchParams.status as Filter)
      : "pending";
  const rows = await fetchClaims(filter);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold text-navy">Church claims</h1>
        <p className="text-sm text-ink/60 mt-1">
          People applying to manage a church. Verify them on WhatsApp, then
          approve — approving unlocks the church-admin dashboard in the app so
          they can post announcements and edit their church profile.
        </p>
      </header>

      <FilterTabs current={filter} />

      {rows.length === 0 ? (
        <EmptyState filter={filter} />
      ) : (
        <ul className="space-y-3">
          {rows.map((row) => (
            <ClaimCard key={row.id} row={row} />
          ))}
        </ul>
      )}
    </div>
  );
}

function FilterTabs({ current }: { current: Filter }) {
  const tabs: { value: Filter; label: string }[] = [
    { value: "pending", label: "Pending" },
    { value: "approved", label: "Approved" },
    { value: "rejected", label: "Rejected" },
    { value: "all", label: "All" },
  ];
  return (
    <div className="flex gap-2 border-b border-ink/10">
      {tabs.map((tab) => (
        <Link
          key={tab.value}
          href={`/church-claims?status=${tab.value}`}
          className={`px-4 py-2 text-sm font-semibold border-b-2 -mb-px transition-colors ${
            current === tab.value
              ? "border-primary text-primary"
              : "border-transparent text-ink/60 hover:text-ink"
          }`}
        >
          {tab.label}
        </Link>
      ))}
    </div>
  );
}

function ClaimCard({ row }: { row: ClaimRow }) {
  const name = row.applicant_name?.trim() || "Unknown applicant";
  const initial = name.slice(0, 1).toUpperCase();
  const churchName = row.churches?.name ?? `Church #${row.church_id}`;
  const churchCity = row.churches?.city;
  const submittedAt = new Date(row.created_at).toLocaleString();
  const waNumber = row.applicant_phone?.replace(/[^0-9]/g, "") ?? "";

  return (
    <li className="bg-white border border-ink/5 rounded-2xl p-5 shadow-sm">
      <div className="flex items-start gap-4">
        <div className="w-10 h-10 rounded-full bg-primary text-white grid place-items-center font-bold">
          {initial}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <h3 className="font-bold text-navy">{name}</h3>
            <span className="text-xs text-ink/55">· {submittedAt}</span>
          </div>
          <div className="mt-1 text-sm text-ink/75">
            Wants to manage{" "}
            <span className="font-semibold text-navy">{churchName}</span>
            {churchCity ? `, ${churchCity}` : ""}
            <StatusBadge status={row.status} />
          </div>

          {/* Contact — spelled out so the founder can verify exactly who applied. */}
          <div className="mt-3 grid gap-1.5 text-sm">
            <div>
              <span className="text-ink/50">Phone: </span>
              <span className="font-semibold text-navy select-all">
                {row.applicant_phone || "—"}
              </span>
            </div>
            <div>
              <span className="text-ink/50">Email: </span>
              <span className="font-semibold text-navy select-all">
                {row.applicant_email || "—"}
              </span>
            </div>
          </div>

          <div className="mt-3 flex flex-wrap gap-2 text-xs">
            {row.applicant_email && (
              <a
                href={`mailto:${row.applicant_email}?subject=${encodeURIComponent(`Re: managing ${churchName} on Advent Connect ZW`)}`}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-primary/10 text-primary font-semibold hover:bg-primary/15"
              >
                ✉️ Email
              </a>
            )}
            {waNumber && (
              <a
                href={`https://wa.me/${waNumber}?text=${encodeURIComponent(`Hi ${name}, this is about your Advent Connect ZW request to manage ${churchName}. `)}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-ok/15 text-ok font-semibold hover:bg-ok/25"
              >
                💬 WhatsApp
              </a>
            )}
          </div>

          {row.applicant_note && (
            <p className="text-sm text-ink/75 mt-3 whitespace-pre-line">
              {row.applicant_note}
            </p>
          )}

          {row.rejection_reason && row.status === "rejected" && (
            <div className="mt-3 text-xs bg-canvas border border-ink/10 rounded-lg px-3 py-2 text-ink/70">
              <span className="font-semibold uppercase tracking-wide text-ink/55">
                Decline reason
              </span>
              <div className="mt-1 whitespace-pre-line">
                {row.rejection_reason}
              </div>
            </div>
          )}
        </div>
      </div>

      {row.status === "pending" && (
        <div className="mt-4 pt-4 border-t border-ink/5">
          <ReviewForm claimId={row.id} />
        </div>
      )}
    </li>
  );
}

function StatusBadge({ status }: { status: ClaimRow["status"] }) {
  const map: Record<ClaimRow["status"], { label: string; classes: string }> = {
    pending: { label: "Pending", classes: "bg-gold/20 text-gold border-gold/40" },
    approved: { label: "Approved", classes: "bg-ok/15 text-ok border-ok/40" },
    rejected: { label: "Rejected", classes: "bg-warn/15 text-warn border-warn/40" },
  };
  const meta = map[status];
  return (
    <span
      className={`ml-2 inline-block px-2 py-0.5 rounded-full border text-[11px] font-bold uppercase tracking-wider ${meta.classes}`}
    >
      {meta.label}
    </span>
  );
}

function EmptyState({ filter }: { filter: Filter }) {
  return (
    <div className="bg-white border border-ink/5 rounded-2xl p-10 text-center">
      <div className="text-4xl">⛪</div>
      <h3 className="font-bold text-navy mt-3">Nothing here</h3>
      <p className="text-sm text-ink/60 mt-1">
        No {filter === "all" ? "" : filter} church claims right now.
      </p>
    </div>
  );
}

// Server-action buttons via `formAction` — no client component needed.
function ReviewForm({ claimId }: { claimId: number }) {
  return (
    <form className="flex flex-col gap-3">
      <textarea
        name="reviewerNote"
        rows={2}
        placeholder="Optional note (required when declining) — visible to the applicant."
        className="w-full px-3 py-2 text-sm rounded-lg border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary"
      />
      <div className="flex flex-wrap gap-2 justify-end">
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const note = (formData.get("reviewerNote") as string) ?? "";
            await rejectChurchClaimAction(claimId, note);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg border border-warn/40 text-warn hover:bg-warn/10"
        >
          Decline
        </button>
        <button
          type="submit"
          formAction={async () => {
            "use server";
            await approveChurchClaimAction(claimId);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg bg-primary text-white hover:opacity-95"
        >
          Approve
        </button>
      </div>
    </form>
  );
}
