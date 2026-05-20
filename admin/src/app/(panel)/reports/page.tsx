import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import { setReportStatusAction } from "./actions";
import Link from "next/link";

type Filter = "pending" | "reviewing" | "actioned" | "dismissed" | "all";

type Row = {
  id: number;
  reported_by: string;
  content_type: string;
  content_id: string;
  reason: string;
  details: string | null;
  status: "pending" | "reviewing" | "actioned" | "dismissed";
  action_taken: string | null;
  created_at: string;
  reviewed_at: string | null;
  profiles: { full_name: string | null; profile_photo_url: string | null } | null;
};

async function fetchReports(filter: Filter): Promise<Row[]> {
  const supabase = getServiceSupabase();
  let query = supabase
    .from("reports")
    .select(
      "*, profiles!reports_reported_by_fkey(full_name, profile_photo_url)",
    )
    .order("created_at", { ascending: false })
    .limit(200);
  if (filter !== "all") query = query.eq("status", filter);
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data ?? []) as Row[];
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  await requireAdmin();
  const filter: Filter =
    ["all", "reviewing", "actioned", "dismissed"].includes(
      searchParams.status ?? "",
    )
      ? (searchParams.status as Filter)
      : "pending";
  const rows = await fetchReports(filter);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold text-navy">User reports</h1>
        <p className="text-sm text-ink/60 mt-1">
          Content and people that members have flagged for review.
        </p>
      </header>

      <Tabs current={filter} />

      {rows.length === 0 ? (
        <Empty filter={filter} />
      ) : (
        <ul className="space-y-3">
          {rows.map((row) => (
            <ReportCard key={row.id} row={row} />
          ))}
        </ul>
      )}
    </div>
  );
}

function Tabs({ current }: { current: Filter }) {
  const tabs: { value: Filter; label: string }[] = [
    { value: "pending", label: "Pending" },
    { value: "reviewing", label: "Reviewing" },
    { value: "actioned", label: "Actioned" },
    { value: "dismissed", label: "Dismissed" },
    { value: "all", label: "All" },
  ];
  return (
    <div className="flex gap-2 border-b border-ink/10 overflow-x-auto">
      {tabs.map((tab) => (
        <Link
          key={tab.value}
          href={`/reports?status=${tab.value}`}
          className={`px-4 py-2 text-sm font-semibold border-b-2 -mb-px transition-colors whitespace-nowrap ${
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

function ReportCard({ row }: { row: Row }) {
  const reporterName = row.profiles?.full_name ?? "Unknown member";
  const initial = reporterName.slice(0, 1).toUpperCase();

  return (
    <li className="bg-white border border-ink/5 rounded-2xl p-5 shadow-sm">
      <div className="flex items-start gap-4">
        <div className="w-10 h-10 rounded-full bg-primary text-white grid place-items-center font-bold overflow-hidden">
          {row.profiles?.profile_photo_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.profiles.profile_photo_url}
              alt={reporterName}
              className="w-full h-full object-cover"
            />
          ) : (
            initial
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <span className="font-bold text-navy">{reporterName}</span>
            <span className="text-xs text-ink/55">
              reported · {new Date(row.created_at).toLocaleString()}
            </span>
            <StatusBadge status={row.status} />
          </div>
          <div className="mt-1 text-sm">
            <span className="font-semibold text-navy">{row.reason}</span>
            <span className="text-ink/60">
              {" "}
              on a{" "}
              <span className="font-mono bg-canvas px-1.5 py-0.5 rounded">
                {row.content_type}
              </span>
              {" — "}
              <span className="font-mono text-xs">{row.content_id}</span>
            </span>
          </div>
          {row.details && (
            <p className="text-sm text-ink/75 mt-2 whitespace-pre-line">
              {row.details}
            </p>
          )}
          {row.action_taken && row.status !== "pending" && (
            <div className="mt-3 text-xs bg-canvas border border-ink/10 rounded-lg px-3 py-2 text-ink/70">
              <span className="font-semibold uppercase tracking-wide text-ink/55">
                Action taken
              </span>
              <div className="mt-1 whitespace-pre-line">{row.action_taken}</div>
            </div>
          )}
        </div>
      </div>

      {row.status !== "actioned" && row.status !== "dismissed" && (
        <div className="mt-4 pt-4 border-t border-ink/5">
          <ReviewForm reportId={row.id.toString()} />
        </div>
      )}
    </li>
  );
}

function StatusBadge({ status }: { status: Row["status"] }) {
  const map: Record<Row["status"], { label: string; classes: string }> = {
    pending: { label: "Pending", classes: "bg-gold/20 text-gold border-gold/40" },
    reviewing: {
      label: "Reviewing",
      classes: "bg-primary/10 text-primary border-primary/40",
    },
    actioned: { label: "Actioned", classes: "bg-ok/15 text-ok border-ok/40" },
    dismissed: {
      label: "Dismissed",
      classes: "bg-ink/10 text-ink/60 border-ink/20",
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

function Empty({ filter }: { filter: Filter }) {
  return (
    <div className="bg-white border border-ink/5 rounded-2xl p-10 text-center">
      <div className="text-4xl">🛡️</div>
      <h3 className="font-bold text-navy mt-3">Nothing here</h3>
      <p className="text-sm text-ink/60 mt-1">
        No {filter === "all" ? "" : filter} reports right now.
      </p>
    </div>
  );
}

function ReviewForm({ reportId }: { reportId: string }) {
  return (
    <form className="flex flex-col gap-3">
      <textarea
        name="actionTaken"
        rows={2}
        placeholder="What did you do? (e.g. 'Removed the post and warned the author', 'No violation found'.)"
        className="w-full px-3 py-2 text-sm rounded-lg border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary"
      />
      <div className="flex flex-wrap gap-2 justify-end">
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const note = (formData.get("actionTaken") as string) ?? "";
            await setReportStatusAction(reportId, "dismissed", note || null);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg border border-ink/15 text-ink/75 hover:bg-ink/5"
        >
          Dismiss
        </button>
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const note = (formData.get("actionTaken") as string) ?? "";
            await setReportStatusAction(reportId, "reviewing", note || null);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg border border-primary/40 text-primary hover:bg-primary/10"
        >
          Mark reviewing
        </button>
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const note = (formData.get("actionTaken") as string) ?? "";
            await setReportStatusAction(reportId, "actioned", note || null);
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg bg-primary text-white hover:opacity-95"
        >
          Mark actioned
        </button>
      </div>
    </form>
  );
}
