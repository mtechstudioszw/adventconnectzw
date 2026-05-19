import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import Link from "next/link";

async function fetchCounts() {
  const supabase = getServiceSupabase();

  const [
    profiles,
    sevenDay,
    businessApplications,
    pendingApplications,
    posts,
    stories,
    bannedUsers,
  ] = await Promise.all([
    supabase.from("profiles").select("id", { count: "exact", head: true }),
    supabase
      .from("profiles")
      .select("id", { count: "exact", head: true })
      .gte(
        "created_at",
        new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
      ),
    supabase
      .from("business_applications")
      .select("id", { count: "exact", head: true }),
    supabase
      .from("business_applications")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending"),
    supabase.from("posts").select("id", { count: "exact", head: true }),
    supabase
      .from("stories")
      .select("id", { count: "exact", head: true })
      .gt("expires_at", new Date().toISOString()),
    supabase
      .from("profiles")
      .select("id", { count: "exact", head: true })
      .eq("is_banned", true),
  ]);

  return {
    totalUsers: profiles.count ?? 0,
    newUsers7d: sevenDay.count ?? 0,
    totalApplications: businessApplications.count ?? 0,
    pendingApplications: pendingApplications.count ?? 0,
    totalPosts: posts.count ?? 0,
    activeStories: stories.count ?? 0,
    bannedUsers: bannedUsers.count ?? 0,
  };
}

export default async function DashboardPage() {
  await requireAdmin();
  const counts = await fetchCounts();

  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-2xl font-bold text-navy">Dashboard</h1>
        <p className="text-sm text-ink/60 mt-1">
          A snapshot of what&apos;s happening across Advent Connect ZW.
        </p>
      </header>

      <section className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Total users"
          value={counts.totalUsers}
          sublabel={`${counts.newUsers7d} new in last 7d`}
        />
        <StatCard
          label="Pending applications"
          value={counts.pendingApplications}
          sublabel={`${counts.totalApplications} all-time`}
          tone={counts.pendingApplications > 0 ? "warn" : "neutral"}
          href="/applications"
        />
        <StatCard
          label="Posts"
          value={counts.totalPosts}
          sublabel="Permanent feed posts"
        />
        <StatCard
          label="Active stories"
          value={counts.activeStories}
          sublabel="Expire within 24h"
        />
        <StatCard
          label="Banned users"
          value={counts.bannedUsers}
          sublabel="Currently blocked"
          tone={counts.bannedUsers > 0 ? "warn" : "neutral"}
          href="/users?filter=banned"
        />
      </section>

      <section className="bg-white rounded-2xl border border-ink/5 p-6">
        <h2 className="font-bold text-navy mb-3">Where to next</h2>
        <ul className="space-y-2 text-sm">
          <li>
            <Link
              className="text-primary font-semibold hover:underline"
              href="/applications?status=pending"
            >
              Review pending business applications →
            </Link>
          </li>
          <li>
            <Link
              className="text-primary font-semibold hover:underline"
              href="/users"
            >
              Browse users / block / warn →
            </Link>
          </li>
          <li>
            <Link
              className="text-primary font-semibold hover:underline"
              href="/announcements"
            >
              Broadcast an announcement →
            </Link>
          </li>
        </ul>
      </section>
    </div>
  );
}

function StatCard({
  label,
  value,
  sublabel,
  tone = "neutral",
  href,
}: {
  label: string;
  value: number;
  sublabel?: string;
  tone?: "neutral" | "warn";
  href?: string;
}) {
  const accent = tone === "warn" ? "text-warn" : "text-navy";
  const Wrapper = ({ children }: { children: React.ReactNode }) =>
    href ? (
      <Link href={href} className="block">
        {children}
      </Link>
    ) : (
      <div>{children}</div>
    );
  return (
    <Wrapper>
      <div className="bg-white rounded-2xl border border-ink/5 p-5 hover:shadow-md transition-shadow">
        <div className="text-xs uppercase tracking-wider text-ink/50 font-semibold">
          {label}
        </div>
        <div className={`mt-2 text-3xl font-bold ${accent}`}>{value}</div>
        {sublabel && (
          <div className="text-xs text-ink/55 mt-1">{sublabel}</div>
        )}
      </div>
    </Wrapper>
  );
}
