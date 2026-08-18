"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useSession } from "@/lib/session";
import { BadgeProvider } from "@/components/Badges";
import { Shell } from "@/components/Shell";

/**
 * The console's front door.
 *
 * This gate is a courtesy, not the security boundary. Anyone can load this
 * bundle; what they cannot do is get an answer out of it, because every
 * `admin_*` RPC re-checks the caller's role in the database. So this is here
 * to route people sensibly, not to protect anything.
 */
export default function ConsoleLayout({ children }: { children: React.ReactNode }) {
  const { session, role, loading } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!session || !role) router.replace("/login");
  }, [loading, session, role, router]);

  if (loading || !session || !role) {
    // Holds the shell's shape while the role lookup settles, so signing in
    // does not flash an empty page before the sidebar appears.
    return (
      <div className="shell">
        <aside className="sidebar">
          <div className="brand">
            <div className="brand-mark">AC</div>
            <div>
              <div className="brand-name">Adventist Super App</div>
              <div className="brand-sub">Admin</div>
            </div>
          </div>
          <div className="nav" style={{ padding: "8px 12px", display: "grid", gap: 8 }}>
            {Array.from({ length: 8 }).map((_, i) => (
              <div className="skeleton" key={i} style={{ height: 30 }} />
            ))}
          </div>
        </aside>
        <div className="main">
          <div className="content">
            <div className="skeleton" style={{ height: 22, width: 190 }} />
            <div className="tiles" style={{ marginTop: 22 }}>
              {Array.from({ length: 6 }).map((_, i) => (
                <div className="tile" key={i}>
                  <div className="skeleton" style={{ height: 11, width: "58%" }} />
                  <div
                    className="skeleton"
                    style={{ height: 26, width: "40%", marginTop: 10 }}
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <BadgeProvider enabled>
      <Shell>{children}</Shell>
    </BadgeProvider>
  );
}
