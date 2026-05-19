import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import {
  createAnnouncementAction,
  deleteAnnouncementAction,
} from "./actions";

type Row = {
  id: string;
  title: string;
  body: string;
  audience: "all" | "business" | "personal";
  severity: "info" | "urgent";
  created_at: string;
};

async function fetchAnnouncements(): Promise<Row[]> {
  const supabase = getServiceSupabase();
  const { data, error } = await supabase
    .from("admin_announcements")
    .select("id, title, body, audience, severity, created_at")
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw new Error(error.message);
  return (data ?? []) as Row[];
}

export default async function AnnouncementsPage() {
  await requireAdmin();
  const rows = await fetchAnnouncements();

  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-2xl font-bold text-navy">Announcements</h1>
        <p className="text-sm text-ink/60 mt-1">
          Broadcast a message to everyone using Advent Connect ZW. Urgent
          severity surfaces as the home-screen red strip; info is a softer
          in-app banner.
        </p>
      </header>

      <section className="bg-white border border-ink/5 rounded-2xl p-6">
        <h2 className="font-bold text-navy mb-4">New announcement</h2>
        <form action={createAnnouncementAction} className="space-y-4">
          <div className="space-y-1">
            <label
              htmlFor="title"
              className="text-xs font-semibold text-ink/70"
            >
              Title
            </label>
            <input
              id="title"
              name="title"
              required
              maxLength={120}
              placeholder="e.g. Server maintenance tonight, 8–10pm"
              className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary text-sm"
            />
          </div>
          <div className="space-y-1">
            <label
              htmlFor="body"
              className="text-xs font-semibold text-ink/70"
            >
              Message
            </label>
            <textarea
              id="body"
              name="body"
              rows={4}
              required
              maxLength={2000}
              placeholder="What do you want everyone to know?"
              className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary text-sm"
            />
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <label
                htmlFor="audience"
                className="text-xs font-semibold text-ink/70"
              >
                Audience
              </label>
              <select
                id="audience"
                name="audience"
                defaultValue="all"
                className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary text-sm"
              >
                <option value="all">Everyone</option>
                <option value="business">Business accounts only</option>
                <option value="personal">Personal accounts only</option>
              </select>
            </div>
            <div className="space-y-1">
              <label
                htmlFor="severity"
                className="text-xs font-semibold text-ink/70"
              >
                Severity
              </label>
              <select
                id="severity"
                name="severity"
                defaultValue="info"
                className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:outline-none focus:border-primary text-sm"
              >
                <option value="info">Info — soft banner</option>
                <option value="urgent">Urgent — red strip</option>
              </select>
            </div>
          </div>
          <div className="flex justify-end pt-2">
            <button
              type="submit"
              className="px-5 py-2.5 rounded-xl bg-primary text-white text-sm font-semibold hover:opacity-95"
            >
              Publish
            </button>
          </div>
        </form>
      </section>

      <section>
        <h2 className="font-bold text-navy mb-3">Recent</h2>
        {rows.length === 0 ? (
          <div className="bg-white border border-ink/5 rounded-2xl p-8 text-center text-sm text-ink/60">
            Nothing published yet.
          </div>
        ) : (
          <ul className="space-y-3">
            {rows.map((row) => (
              <li
                key={row.id}
                className="bg-white border border-ink/5 rounded-2xl p-5"
              >
                <div className="flex items-start gap-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex flex-wrap items-baseline gap-x-2">
                      <h3 className="font-bold text-navy">{row.title}</h3>
                      <span className="text-[10px] font-bold uppercase tracking-wider text-ink/55">
                        {row.audience} · {row.severity}
                      </span>
                    </div>
                    <p className="text-sm text-ink/75 mt-2 whitespace-pre-line">
                      {row.body}
                    </p>
                    <p className="text-xs text-ink/50 mt-3">
                      {new Date(row.created_at).toLocaleString()}
                    </p>
                  </div>
                  <form
                    action={async () => {
                      "use server";
                      await deleteAnnouncementAction(row.id);
                    }}
                  >
                    <button
                      type="submit"
                      className="text-xs font-bold uppercase tracking-wider text-warn px-2 py-1 rounded hover:bg-warn/10"
                    >
                      Delete
                    </button>
                  </form>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
