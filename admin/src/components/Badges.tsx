"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { rpc, rpcList } from "@/lib/rpc";

export type BadgeKey =
  | "sellers"
  | "reports"
  | "feedback"
  | "news"
  | "events"
  | "jobs"
  | "claims";

export type Badges = Partial<Record<BadgeKey, number>>;

type BadgeApi = {
  badges: Badges;
  /** Call after anything that clears an item, so the sidebar count follows. */
  refresh: () => void;
};

const Ctx = createContext<BadgeApi | null>(null);

type OverviewStats = {
  pending_sellers?: number;
  open_reports?: number;
  untriaged_feedback?: number;
  pending_news?: number;
};

export function BadgeProvider({
  enabled,
  children,
}: {
  enabled: boolean;
  children: React.ReactNode;
}) {
  const [badges, setBadges] = useState<Badges>({});
  const [nonce, setNonce] = useState(0);

  const refresh = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    if (!enabled) return;
    let alive = true;

    // Each count is independent and any of them may be refused by role — a
    // viewer cannot list reports. Settling them separately means one denial
    // hides one badge instead of blanking the whole sidebar.
    const set = (key: BadgeKey, n: number) => {
      if (alive) setBadges((b) => (b[key] === n ? b : { ...b, [key]: n }));
    };

    rpc<OverviewStats>("admin_overview_stats")
      .then((s) => {
        set("sellers", Number(s?.pending_sellers ?? 0));
        set("reports", Number(s?.open_reports ?? 0));
        set("feedback", Number(s?.untriaged_feedback ?? 0));
        if (s?.pending_news != null) set("news", Number(s.pending_news));
      })
      .catch(() => {});

    // These three have no counter in `admin_overview_stats`. The lists are
    // small and gated server-side, so counting them directly is cheaper than
    // adding a migration for three integers.
    rpcList("admin_list_pending_church_admins")
      .then((r) => set("claims", r.length))
      .catch(() => {});
    rpcList("admin_list_pending_events")
      .then((r) => set("events", r.length))
      .catch(() => {});
    rpcList("admin_list_pending_jobs")
      .then((r) => set("jobs", r.length))
      .catch(() => {});

    return () => {
      alive = false;
    };
  }, [enabled, nonce]);

  const value = useMemo<BadgeApi>(() => ({ badges, refresh }), [badges, refresh]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useBadges(): BadgeApi {
  const v = useContext(Ctx);
  // Pages call `refresh()` freely; outside the console shell that is a no-op
  // rather than a crash.
  return v ?? { badges: {}, refresh: () => {} };
}
