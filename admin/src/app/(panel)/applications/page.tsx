import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import {
  approveApplicationAction,
  rejectApplicationAction,
} from "./actions";
import Link from "next/link";

type Filter = "pending" | "all" | "approved" | "rejected";

type ApplicationRow = {
  id: string;
  user_id: string;
  business_name: string;
  category: string;
  description: string | null;
  applicant_whatsapp: string | null;
  status: "pending" | "approved" | "rejected";
  created_at: string;
  reviewed_at: string | null;
  reviewer_note: string | null;
  profiles: {
    id: string;
    full_name: string | null;
    profile_photo_url: string | null;
  } | null;
  applicant_email?: string | null;
};

async function fetchApplications(filter: Filter): Promise<ApplicationRow[]> {
  const supabase = getServiceSupabase();
  let query = supabase
    .from("business_applications")
    .select(
      "*, profiles!business_applications_user_id_fkey(id, full_name, profile_photo_url)",
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
  const rows = (data ?? []) as ApplicationRow[];

  // Top up each row with the applicant's auth.users email. We do this
  // in one extra fetch because foreign tables can't be embedded via
  // PostgREST. Returns null if the lookup fails — UI handles it.
  if (rows.length > 0) {
    const userIds = Array.from(new Set(rows.map((r) => r.user_id)));
    const emailMap = new Map<string, string>();
    for (const id of userIds) {
      const { data: u } = await supabase.auth.admin.getUserById(id);
      if (u.user?.email) emailMap.set(id, u.user.email);
    }
    for (const row of rows) {
      row.applicant_email = emailMap.get(row.user_id) ?? null;
    }
  }
  return rows;
}

export default async function ApplicationsPage({
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
  const rows = await fetchApplications(filter);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold text-navy">Business applications</h1>
        <p className="text-sm text-ink/60 mt-1">
          Approve or decline applications. Approving flips the user&apos;s
          <span className="font-medium"> is_business</span> flag so they
          unlock selling and church-claim in the app.
        </p>
      </header>

      <FilterTabs current={filter} />

      {rows.length === 0 ? (
        <EmptyState filter={filter} />
      ) : (
        <ul className="space-y-3">
          {rows.map((row) => (
            <ApplicationCard key={row.id} row={row} />
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
          href={`/applications?status=${tab.value}`}
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

function ApplicationCard({ row }: { row: ApplicationRow }) {
  const name = row.profiles?.full_name ?? "Unknown member";
  const photo = row.profiles?.profile_photo_url;
  const initial = name.trim().slice(0, 1).toUpperCase();
  const submittedAt = new Date(row.created_at).toLocaleString();

  return (
    <li className="bg-white border border-ink/5 rounded-2xl p-5 shadow-sm">
      <div className="flex items-start gap-4">
        <div className="w-10 h-10 rounded-full bg-primary text-white grid place-items-center font-bold overflow-hidden">
          {photo ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={photo}
              alt={name}
              className="w-full h-full object-cover"
            />
          ) : (
            initial
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <h3 className="font-bold text-navy">{row.business_name}</h3>
            <span className="text-xs text-ink/55">
              by {name} · {submittedAt}
            </span>
          </div>
          <div className="mt-1 text-xs">
            <span className="inline-block px-2 py-0.5 rounded-full bg-canvas border border-ink/10 text-ink/70">
              {row.category}
            </span>
            <StatusBadge status={row.status} />
          </div>
          <div className="mt-3 flex flex-wrap gap-2 text-xs">
            {row.applicant_email && (
              <a
                href={`mailto:${row.applicant_email}?subject=${encodeURIComponent(`Re: ${row.business_name} business application`)}`}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-primary/10 text-primary font-semibold hover:bg-primary/15"
              >
                ✉️ {row.applicant_email}
              </a>
            )}
            {row.applicant_whatsapp && (
              <a
                href={`https://wa.me/${row.applicant_whatsapp.replace(/[^0-9]/g, "")}?text=${encodeURIComponent(`Hi ${row.profiles?.full_name ?? ""}, this is about your Advent Connect ZW business application for "${row.business_name}". `)}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-ok/15 text-ok font-semibold hover:bg-ok/25"
              >
                💬 {row.applicant_whatsapp}
              </a>
            )}
          </div>
          {row.description && (
            <p className="text-sm text-ink/75 mt-3 whitespace-pre-line">
              {row.description}
            </p>
          )}
          {row.reviewer_note && row.status !== "pending" && (
            <div className="mt-3 text-xs bg-canvas border border-ink/10 rounded-lg px-3 py-2 text-ink/70">
              <span className="font-semibold uppercase tracking-wide text-ink/55">
                Note
              </span>
              <div className="mt-1 whitespace-pre-line">
                {row.reviewer_note}
              </div>
            </div>
          )}
        </div>
      </div>

      {row.status === "pending" && (
        <div className="mt-4 pt-4 border-t border-ink/5">
          <ReviewForm applicationId={row.id} />
        </div>
      )}
    </li>
  );
}

function StatusBadge({ status }: { status: ApplicationRow["status"] }) {
  const map: Record<
    ApplicationRow["status"],
    { label: string; classes: string }
  > = {
    pending: {
      label: "Pending",
      classes: "bg-gold/20 text-gold border-gold/40",
    },
    approved: {
      label: "Approved",
      classes: "bg-ok/15 text-ok border-ok/40",
    },
    rejected: {
      label: "Rejected",
      classes: "bg-warn/15 text-warn border-warn/40",
    },
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
      <div className="text-4xl">🪴</div>
      <h3 className="font-bold text-navy mt-3">Nothing here</h3>
      <p className="text-sm text-ink/60 mt-1">
        No {filter === "all" ? "" : filter} applications right now.
      </p>
    </div>
  );
}

// The form uses server actions directly via the `formAction` attribute
// so we don't need a client component just for the buttons.
function ReviewForm({ applicationId }: { applicationId: string }) {
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
            await rejectApplicationAction(applicationId, note);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg border border-warn/40 text-warn hover:bg-warn/10"
        >
          Decline
        </button>
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const note = (formData.get("reviewerNote") as string) ?? "";
            await approveApplicationAction(applicationId, note || null);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg bg-primary text-white hover:opacity-95"
        >
          Approve
        </button>
      </div>
    </form>
  );
}
