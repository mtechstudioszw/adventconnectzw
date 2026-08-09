"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "./supabase";
import { rpc } from "./rpc";

/**
 * Staff roles, least privilege first. Mirrors `staff_rank()` in
 * `20260803150000_staff_roles_and_audit.sql` — if that migration ever gains a
 * role, this list is the other half of the change.
 */
export const ROLES = ["viewer", "moderator", "manager", "owner"] as const;
export type Role = (typeof ROLES)[number];

export const ROLE_BLURB: Record<Role, string> = {
  viewer: "Can read everything. Changes nothing.",
  moderator: "Clears the queues. Contact details stay hidden.",
  manager: "Everything a moderator does, plus contact details and the audit log.",
  owner: "Full control — bans, broadcasts, maintenance and staff.",
};

export function rank(role: Role | null): number {
  return role ? ROLES.indexOf(role) : -1;
}

/** True when `role` is at least `min`. The server checks this again. */
export function atLeast(role: Role | null, min: Role): boolean {
  return rank(role) >= rank(min);
}

export type MaintenanceState = {
  active: boolean;
  message: string;
  ends_at: string | null;
};

type SessionValue = {
  session: Session | null;
  email: string | null;
  role: Role | null;
  loading: boolean;
  /** Set when a valid Supabase session exists but the account is not staff. */
  notStaff: boolean;
  maintenance: MaintenanceState;
  refreshMaintenance: () => Promise<void>;
  signOut: () => Promise<void>;
  can: (min: Role) => boolean;
};

const Ctx = createContext<SessionValue | null>(null);

const MAINTENANCE_OFF: MaintenanceState = {
  active: false,
  message: "",
  ends_at: null,
};

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [loading, setLoading] = useState(true);
  const [notStaff, setNotStaff] = useState(false);
  const [maintenance, setMaintenance] = useState<MaintenanceState>(MAINTENANCE_OFF);

  // Guards against a slow role lookup from a previous session landing after a
  // faster one from the current session and overwriting it.
  const generation = useRef(0);

  const refreshMaintenance = useCallback(async () => {
    try {
      const rows = await rpc<MaintenanceState[] | null>("maintenance_status");
      const row = Array.isArray(rows) ? rows[0] : null;
      setMaintenance(
        row
          ? {
              active: row.active === true,
              message: row.message ?? "",
              ends_at: row.ends_at ?? null,
            }
          : MAINTENANCE_OFF,
      );
    } catch {
      // Never block the console on this. It is a banner, not a gate — and the
      // one time it is most likely to fail is while the database is being
      // worked on, which is exactly when the console must still open.
    }
  }, []);

  const loadRole = useCallback(
    async (next: Session | null) => {
      const gen = ++generation.current;
      if (!next) {
        setRole(null);
        setNotStaff(false);
        setLoading(false);
        return;
      }
      try {
        // `current_staff_role()` already folds in the legacy
        // `profiles.is_super_admin` flag, so the founder's own account keeps
        // working without a staff_members row being required first.
        const r = await rpc<Role | null>("current_staff_role");
        if (gen !== generation.current) return;
        setRole(r ?? null);
        setNotStaff(!r);
      } catch {
        if (gen !== generation.current) return;
        setRole(null);
        setNotStaff(true);
      } finally {
        if (gen === generation.current) setLoading(false);
      }
    },
    [],
  );

  useEffect(() => {
    const sb = supabase();
    let alive = true;

    sb.auth.getSession().then(({ data }) => {
      if (!alive) return;
      setSession(data.session);
      void loadRole(data.session);
      if (data.session) void refreshMaintenance();
    });

    const { data: sub } = sb.auth.onAuthStateChange((_event, next) => {
      if (!alive) return;
      setSession(next);
      void loadRole(next);
      if (next) void refreshMaintenance();
      else setMaintenance(MAINTENANCE_OFF);
    });

    return () => {
      alive = false;
      sub.subscription.unsubscribe();
    };
  }, [loadRole, refreshMaintenance]);

  // Re-check maintenance on a slow loop while the console is open. Two people
  // can be working at once, and the banner claiming the app is up when an
  // owner turned it off ten minutes ago is worse than no banner.
  useEffect(() => {
    if (!session) return;
    const id = window.setInterval(() => void refreshMaintenance(), 60_000);
    const onFocus = () => void refreshMaintenance();
    window.addEventListener("focus", onFocus);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("focus", onFocus);
    };
  }, [session, refreshMaintenance]);

  const signOut = useCallback(async () => {
    await supabase().auth.signOut();
    setSession(null);
    setRole(null);
    setNotStaff(false);
    setMaintenance(MAINTENANCE_OFF);
  }, []);

  const value = useMemo<SessionValue>(
    () => ({
      session,
      email: session?.user?.email ?? null,
      role,
      loading,
      notStaff,
      maintenance,
      refreshMaintenance,
      signOut,
      can: (min: Role) => atLeast(role, min),
    }),
    [session, role, loading, notStaff, maintenance, refreshMaintenance, signOut],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSession(): SessionValue {
  const v = useContext(Ctx);
  if (!v) throw new Error("useSession must be used inside <SessionProvider>");
  return v;
}
