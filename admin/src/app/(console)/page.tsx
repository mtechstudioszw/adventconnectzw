"use client";

import Link from "next/link";
import { useCallback } from "react";
import { rpc } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useSession } from "@/lib/session";
import { fmtNum, pct } from "@/lib/format";
import { Empty, ErrorBox, Note, PageHead, Tile, TilesSkeleton } from "@/components/ui";
import { IconRefresh } from "@/components/icons";

type OverviewStats = {
  pending_sellers: number;
  open_reports: number;
  untriaged_feedback: number;
  pending_news?: number;
  total_users: number;
  new_users_7d: number;
  banned_users: number;
};

type UsageStats = {
  total_users: number;
  active_1d: number;
  active_7d: number;
  active_30d: number;
  new_1d: number;
  new_7d: number;
  messages: number;
  posts: number;
  prayers: number;
};

export default function OverviewPage() {
  const { role, maintenance } = useSession();

  const load = useCallback(
    () =>
      Promise.all([
        rpc<OverviewStats>("admin_overview_stats"),
        // Tolerated separately: a viewer may be refused this one, and losing
        // the activity strip should not blank the attention counts.
        rpc<UsageStats>("admin_usage_stats").catch(() => null),
      ]),
    [],
  );

  const { data, error, loading, reload } = useAsync(load, []);
  const [stats, usage] = data ?? [null, null];

  const queue =
    (stats?.pending_sellers ?? 0) +
    (stats?.open_reports ?? 0) +
    (stats?.untriaged_feedback ?? 0) +
    (stats?.pending_news ?? 0);

  return (
    <div className="stack">
      <PageHead
        title={greeting()}
        sub={
          loading
            ? "Loading today's numbers…"
            : queue > 0
              ? `${queue} thing${queue === 1 ? "" : "s"} waiting for a decision.`
              : "Nothing is waiting for a decision. The queues are clear."
        }
        actions={
          <button className="btn ghost" onClick={reload} disabled={loading}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />

      {error ? <ErrorBox message={error} /> : null}

      {maintenance.active ? (
        <div className="maint-hero on">
          <div className="maint-state">
            <span className="pulse" />
          </div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div className="maint-title">Adventist Super App is offline</div>
            <p className="meta">
              Every member sees the maintenance screen and no content can be
              written. Only you can put it back.
            </p>
          </div>
          <Link className="btn solid-red" href="/maintenance">
            Bring the app back
          </Link>
        </div>
      ) : null}

      {loading && !stats ? (
        <TilesSkeleton count={6} />
      ) : stats ? (
        <>
          <section>
            <div className="section-title">Waiting for you</div>
            <div className="tiles">
              <LinkTile
                href="/reports"
                label="Open reports"
                value={stats.open_reports}
                sub="Reported content and accounts"
              />
              <LinkTile
                href="/feedback"
                label="New feedback"
                value={stats.untriaged_feedback}
                sub="Members waiting on a reply"
              />
              <LinkTile
                href="/sellers"
                label="Pending sellers"
                value={stats.pending_sellers}
                sub="Storefronts not yet live"
              />
              {stats.pending_news != null ? (
                <LinkTile
                  href="/news"
                  label="News to review"
                  value={stats.pending_news}
                  sub="Stories awaiting approval"
                />
              ) : null}
            </div>
          </section>

          <section>
            <div className="section-title">Membership</div>
            <div className="tiles">
              <Tile label="Total members" value={stats.total_users} />
              <Tile
                label="New this week"
                value={stats.new_users_7d}
                sub={usage ? `${fmtNum(usage.new_1d)} today` : undefined}
              />
              {usage ? (
                <Tile
                  label="Active today"
                  value={usage.active_1d}
                  sub={`${pct(usage.active_1d, usage.total_users)}% of members`}
                />
              ) : null}
              {usage ? (
                <Tile
                  label="Active this week"
                  value={usage.active_7d}
                  sub={`${pct(usage.active_7d, usage.total_users)}% of members`}
                />
              ) : null}
              <Tile label="Banned" value={stats.banned_users} tone="danger" />
            </div>
          </section>

          {usage ? (
            <section>
              <div className="section-title">
                Life in the app
                <span className="count">last 30 days of content</span>
              </div>
              <div className="tiles">
                <Tile label="Messages" value={usage.messages} />
                <Tile label="Posts" value={usage.posts} />
                <Tile label="Prayers" value={usage.prayers} />
              </div>
            </section>
          ) : null}
        </>
      ) : !error ? (
        <Empty title="No numbers came back" sub="Try refreshing." />
      ) : null}

      {role === "viewer" ? (
        <Note>
          You are signed in as a <strong>viewer</strong>. You can read everything
          in this console and change nothing.
        </Note>
      ) : null}
    </div>
  );
}

/** A tile that is also the way into the queue it counts. */
function LinkTile({
  href,
  label,
  value,
  sub,
}: {
  href: string;
  label: string;
  value: number;
  sub: string;
}) {
  return (
    <Link href={href} className={`tile${value > 0 ? " alert" : ""}`}>
      <div className="tile-label">{label}</div>
      <div className="tile-value">{fmtNum(value)}</div>
      <div className="tile-sub">{value > 0 ? sub : "All clear"}</div>
    </Link>
  );
}

function greeting(): string {
  // Harare, not the browser's zone — the team is in one place and "Good
  // evening" at 9am because a laptop is still on UK time is a small lie the
  // console should not tell.
  const hour = Number(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Africa/Harare",
      hour: "numeric",
      hour12: false,
    }).format(new Date()),
  );
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}
