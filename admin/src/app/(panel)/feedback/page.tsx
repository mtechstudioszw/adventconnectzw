import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import { replyToFeedbackAction } from "./actions";
import Link from "next/link";

type Filter = "new" | "triaged" | "in_progress" | "resolved" | "wont_fix" | "all";

type Row = {
  id: number;
  user_id: string;
  category: string;
  subject: string;
  body: string;
  app_version: string | null;
  platform: string | null;
  status: "new" | "triaged" | "in_progress" | "resolved" | "wont_fix";
  triaged_at: string | null;
  resolution_note: string | null;
  created_at: string;
  profiles: { full_name: string | null; profile_photo_url: string | null } | null;
  applicant_email?: string | null;
};

async function fetchFeedback(filter: Filter): Promise<Row[]> {
  const supabase = getServiceSupabase();
  let query = supabase
    .from("feedback")
    .select(
      "*, profiles!feedback_user_id_fkey(full_name, profile_photo_url)",
    )
    .order("created_at", { ascending: false })
    .limit(200);
  if (filter !== "all") query = query.eq("status", filter);
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as Row[];

  if (rows.length > 0) {
    const ids = Array.from(new Set(rows.map((r) => r.user_id)));
    const emailMap = new Map<string, string>();
    for (const id of ids) {
      const { data: u } = await supabase.auth.admin.getUserById(id);
      if (u.user?.email) emailMap.set(id, u.user.email);
    }
    for (const row of rows) {
      row.applicant_email = emailMap.get(row.user_id) ?? null;
    }
  }
  return rows;
}

export default async function FeedbackPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  await requireAdmin();
  const allowed = ["new", "triaged", "in_progress", "resolved", "wont_fix", "all"];
  const filter: Filter = allowed.includes(searchParams.status ?? "")
    ? (searchParams.status as Filter)
    : "new";
  const rows = await fetchFeedback(filter);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold text-navy">User feedback</h1>
        <p className="text-sm text-ink/60 mt-1">
          What members are saying. Replying drops your message into their
          in-app notification inbox.
        </p>
      </header>

      <Tabs current={filter} />

      {rows.length === 0 ? (
        <Empty filter={filter} />
      ) : (
        <ul className="space-y-3">
          {rows.map((row) => (
            <FeedbackCard key={row.id} row={row} />
          ))}
        </ul>
      )}
    </div>
  );
}

function Tabs({ current }: { current: Filter }) {
  const tabs: { value: Filter; label: string }[] = [
    { value: "new", label: "New" },
    { value: "triaged", label: "Triaged" },
    { value: "in_progress", label: "In progress" },
    { value: "resolved", label: "Resolved" },
    { value: "wont_fix", label: "Won't fix" },
    { value: "all", label: "All" },
  ];
  return (
    <div className="flex gap-2 border-b border-ink/10 overflow-x-auto">
      {tabs.map((tab) => (
        <Link
          key={tab.value}
          href={`/feedback?status=${tab.value}`}
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

function FeedbackCard({ row }: { row: Row }) {
  const name = row.profiles?.full_name ?? "Unknown member";
  const initial = name.slice(0, 1).toUpperCase();
  return (
    <li className="bg-white border border-ink/5 rounded-2xl p-5 shadow-sm">
      <div className="flex items-start gap-4">
        <div className="w-10 h-10 rounded-full bg-primary text-white grid place-items-center font-bold overflow-hidden">
          {row.profiles?.profile_photo_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.profiles.profile_photo_url}
              alt={name}
              className="w-full h-full object-cover"
            />
          ) : (
            initial
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-baseline gap-x-2">
            <span className="font-bold text-navy">{row.subject}</span>
            <span className="text-xs text-ink/55">
              by {name} · {new Date(row.created_at).toLocaleString()}
            </span>
            <StatusBadge status={row.status} />
          </div>
          <div className="mt-1 text-xs flex flex-wrap gap-2">
            <span className="px-2 py-0.5 rounded-full bg-canvas border border-ink/10 text-ink/65">
              {row.category}
            </span>
            {row.platform && (
              <span className="px-2 py-0.5 rounded-full bg-canvas border border-ink/10 text-ink/65">
                {row.platform} · v{row.app_version ?? "?"}
              </span>
            )}
            {row.applicant_email && (
              <a
                href={`mailto:${row.applicant_email}?subject=${encodeURIComponent(`Re: ${row.subject}`)}`}
                className="px-2 py-0.5 rounded-full bg-primary/10 text-primary font-semibold hover:bg-primary/15"
              >
                ✉️ {row.applicant_email}
              </a>
            )}
          </div>
          <p className="text-sm text-ink/75 mt-3 whitespace-pre-line">
            {row.body}
          </p>
          {row.resolution_note && (
            <div className="mt-3 text-xs bg-canvas border border-ink/10 rounded-lg px-3 py-2 text-ink/70">
              <span className="font-semibold uppercase tracking-wide text-ink/55">
                Your reply
              </span>
              <div className="mt-1 whitespace-pre-line">
                {row.resolution_note}
              </div>
            </div>
          )}
        </div>
      </div>

      {row.status !== "resolved" && row.status !== "wont_fix" && (
        <div className="mt-4 pt-4 border-t border-ink/5">
          <ReplyForm feedbackId={row.id.toString()} />
        </div>
      )}
    </li>
  );
}

function StatusBadge({ status }: { status: Row["status"] }) {
  const map: Record<Row["status"], { label: string; classes: string }> = {
    new: { label: "New", classes: "bg-warn/15 text-warn border-warn/40" },
    triaged: {
      label: "Triaged",
      classes: "bg-gold/20 text-gold border-gold/40",
    },
    in_progress: {
      label: "In progress",
      classes: "bg-primary/10 text-primary border-primary/40",
    },
    resolved: {
      label: "Resolved",
      classes: "bg-ok/15 text-ok border-ok/40",
    },
    wont_fix: {
      label: "Won't fix",
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
      <div className="text-4xl">💬</div>
      <h3 className="font-bold text-navy mt-3">Nothing here</h3>
      <p className="text-sm text-ink/60 mt-1">
        No {filter === "all" ? "" : filter} feedback right now.
      </p>
    </div>
  );
}

function ReplyForm({ feedbackId }: { feedbackId: string }) {
  return (
    <form className="flex flex-col gap-3">
      <textarea
        name="reply"
        rows={3}
        required
        placeholder="Type your reply. The member will receive this as an in-app notification."
        className="w-full px-3 py-2 text-sm rounded-lg border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary"
      />
      <div className="flex flex-wrap gap-2 justify-end">
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const body = (formData.get("reply") as string) ?? "";
            await replyToFeedbackAction(feedbackId, body, "wont_fix");
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg border border-ink/15 text-ink/75 hover:bg-ink/5"
        >
          Reply + Won't fix
        </button>
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const body = (formData.get("reply") as string) ?? "";
            await replyToFeedbackAction(feedbackId, body, "in_progress");
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg border border-primary/40 text-primary hover:bg-primary/10"
        >
          Reply + In progress
        </button>
        <button
          type="submit"
          formAction={async (formData: FormData) => {
            "use server";
            const body = (formData.get("reply") as string) ?? "";
            await replyToFeedbackAction(feedbackId, body, "resolved");
          }}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-lg bg-primary text-white hover:opacity-95"
        >
          Reply + Resolved
        </button>
      </div>
    </form>
  );
}
