"use client";

import { useCallback, useState } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { BarList, LineChart } from "@/components/Charts";
import {
  Empty,
  ErrorBox,
  Note,
  PageHead,
  Segmented,
  Tile,
  TilesSkeleton,
} from "@/components/ui";
import { IconRefresh } from "@/components/icons";
import { fmtNum, pct } from "@/lib/format";

type UsageStats = {
  total_users: number;
  active_1d: number;
  active_7d: number;
  active_30d: number;
  new_1d: number;
  new_7d: number;
  new_30d: number;
  banned: number;
  messages: number;
  conversations: number;
  friendships: number;
  church_follows: number;
  posts: number;
  stories: number;
  prayers: number;
  events: number;
  products: number;
  jobs: number;
  survey_responses: number;
};

type FeatureRow = {
  feature: string;
  label: string;
  category: string;
  users: number;
  opens: number;
  engagements: number;
};

type SeriesRow = { day: string; active_users: number; new_users: number; sessions: number };
type PlatformRow = { platform: string; app_version: string; users: number; sessions: number };
type PremiumStats = {
  premium_users?: number;
  active_subscriptions?: number;
  cancelling?: number;
  expired?: number;
  refunded?: number;
};

const WINDOWS = ["7", "30", "90"] as const;

export default function AnalyticsPage() {
  const [days, setDays] = useState<(typeof WINDOWS)[number]>("30");
  const n = Number(days);

  const load = useCallback(
    () =>
      Promise.all([
        rpc<UsageStats>("admin_usage_stats"),
        // Each of these can legitimately be empty or refused. Settling them
        // individually keeps one missing section from blanking the page.
        rpcList<FeatureRow>("admin_feature_usage", { p_days: n }).catch(() => []),
        rpcList<SeriesRow>("admin_active_users_series", { p_days: n }).catch(() => []),
        rpcList<PlatformRow>("admin_platform_breakdown", { p_days: n }).catch(() => []),
        rpc<PremiumStats>("admin_premium_stats").catch(() => null),
      ]),
    [n],
  );

  const { data, error, loading, reload } = useAsync(load, [n]);
  const [usage, features, series, platforms, premium] = data ?? [null, [], [], [], null];

  // The instrumented analytics and the derived counts answer different
  // questions, and only one of them is switched on. Saying which is which is
  // the difference between "nobody uses Prayer" and "nothing is reporting".
  const hasEvents = features.some((f) => f.opens > 0 || f.users > 0);

  return (
    <div className="stack">
      <PageHead
        title="Analytics"
        sub="What members actually do, and how many of them are here to do it."
        actions={
          <div className="row">
            <Segmented
              options={WINDOWS}
              value={days}
              onChange={setDays}
              labels={{ "7": "7 days", "30": "30 days", "90": "90 days" }}
            />
            <button className="btn ghost" onClick={reload} disabled={loading}>
              <IconRefresh className="btn-icon" size={15} />
              Refresh
            </button>
          </div>
        }
      />

      {error ? <ErrorBox message={error} /> : null}

      {loading && !data ? (
        <TilesSkeleton count={8} />
      ) : usage ? (
        <>
          <section>
            <div className="section-title">Members</div>
            <div className="tiles">
              <Tile label="Total members" value={usage.total_users} />
              <Tile
                label="Active today"
                value={usage.active_1d}
                sub={`${pct(usage.active_1d, usage.total_users)}% of members`}
              />
              <Tile
                label="Active this week"
                value={usage.active_7d}
                sub={`${pct(usage.active_7d, usage.total_users)}% of members`}
              />
              <Tile label="Active this month" value={usage.active_30d} />
              <Tile
                label="New this week"
                value={usage.new_7d}
                sub={`${fmtNum(usage.new_1d)} today`}
              />
              <Tile label="New this month" value={usage.new_30d} />
              <Tile label="Banned" value={usage.banned} tone="danger" />
            </div>
          </section>

          {series.length > 1 ? (
            <section>
              <div className="card card-pad">
                <div className="section-title">
                  Active members per day
                  <span className="count">last {n} days</span>
                </div>
                <LineChart
                  label={`Active members per day over ${n} days`}
                  series={series.map((s) => ({
                    day: s.day,
                    value: Number(s.active_users ?? 0),
                  }))}
                />
              </div>
            </section>
          ) : null}

          <section>
            <div className="card card-pad">
              <div className="section-title">
                Which features get used
                <span className="count">last {n} days</span>
              </div>

              {!hasEvents ? (
                <Note>
                  <strong>Nothing is reporting usage yet.</strong> The tables and
                  reports behind this section are live, but the app is not sending
                  events to them — so this is silence from the phones, not proof
                  that nobody opens these features. The numbers below the fold are
                  counted from real content and are unaffected.
                </Note>
              ) : (
                <BarList
                  showZeroNote
                  data={features.map((f) => ({
                    name: f.label || f.feature,
                    value: Number(f.users ?? 0),
                    sub: `${fmtNum(f.opens)} opens`,
                  }))}
                  unit="members"
                />
              )}
            </div>
          </section>

          <section>
            <div className="section-title">Community &amp; content</div>
            <div className="tiles">
              <Tile
                label="Chat messages"
                value={usage.messages}
                sub={`${fmtNum(usage.conversations)} conversations`}
              />
              <Tile label="Friendships" value={usage.friendships} />
              <Tile label="Church follows" value={usage.church_follows} />
              <Tile label="Posts" value={usage.posts} />
              <Tile label="Stories" value={usage.stories} />
              <Tile label="Prayers" value={usage.prayers} />
              <Tile label="Events" value={usage.events} />
              <Tile label="Products" value={usage.products} />
              <Tile label="Jobs" value={usage.jobs} />
            </div>
          </section>

          {premium ? (
            <section>
              <div className="section-title">Premium</div>
              <div className="tiles">
                <Tile label="Premium members" value={Number(premium.premium_users ?? 0)} />
                <Tile
                  label="Active subscriptions"
                  value={Number(premium.active_subscriptions ?? 0)}
                />
                <Tile label="Cancelling" value={Number(premium.cancelling ?? 0)} />
                <Tile label="Expired" value={Number(premium.expired ?? 0)} />
                <Tile label="Refunded" value={Number(premium.refunded ?? 0)} tone="danger" />
              </div>
            </section>
          ) : null}

          {platforms.length > 0 ? (
            <section>
              <div className="card card-pad">
                <div className="section-title">
                  Phones &amp; versions
                  <span className="count">last {n} days</span>
                </div>
                <BarList
                  data={platforms.map((p) => ({
                    name: `${p.platform} ${p.app_version}`.trim(),
                    value: Number(p.users ?? 0),
                  }))}
                  unit="members"
                />
              </div>
            </section>
          ) : null}
        </>
      ) : !error ? (
        <Empty title="No numbers came back" sub="Try refreshing." />
      ) : null}
    </div>
  );
}
