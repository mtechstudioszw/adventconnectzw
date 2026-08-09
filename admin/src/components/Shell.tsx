"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { NAV, NAV_GROUPS, PAGE_META } from "@/lib/nav";
import { atLeast, useSession } from "@/lib/session";
import { initials } from "@/lib/format";
import { useBadges } from "./Badges";
import { IconLogout, IconMenu } from "./icons";

export function Shell({ children }: { children: React.ReactNode }) {
  const { email, role, signOut, maintenance } = useSession();
  const { badges } = useBadges();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  // Close the mobile drawer on navigation, or it stays over the page you
  // just asked for.
  useEffect(() => setOpen(false), [pathname]);

  const meta = PAGE_META[pathname] ?? { title: "Advent Connect" };
  const visible = NAV.filter((item) => atLeast(role, item.min));

  return (
    <div className="shell">
      <aside className={`sidebar${open ? " open" : ""}`}>
        <div className="brand">
          <div className="brand-mark">AC</div>
          <div style={{ minWidth: 0 }}>
            <div className="brand-name">Advent Connect</div>
            <div className="brand-sub">Admin</div>
          </div>
        </div>

        <nav className="nav">
          {NAV_GROUPS.map((group) => {
            const items = visible.filter((i) => i.group === group);
            if (!items.length) return null;
            return (
              <div key={group}>
                <div className="nav-group">{group}</div>
                {items.map((item) => {
                  const Icon = item.icon;
                  const active = pathname === item.href;
                  const count = item.badge ? badges[item.badge] ?? 0 : 0;
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      className={`nav-item${active ? " active" : ""}`}
                      aria-current={active ? "page" : undefined}
                    >
                      <Icon className="nav-icon" size={17} />
                      <span className="nav-label">{item.label}</span>
                      {count > 0 ? <span className="nav-badge">{count}</span> : null}
                    </Link>
                  );
                })}
              </div>
            );
          })}
        </nav>

        <div className="sidebar-foot">
          <div className="avatar">{initials(email)}</div>
          <div className="who">
            <div className="who-email" title={email ?? ""}>
              {email ?? "—"}
            </div>
            <div className="who-role">{role ?? "no role"}</div>
          </div>
          <button
            className="btn ghost sm"
            onClick={() => void signOut()}
            title="Sign out"
            aria-label="Sign out"
          >
            <IconLogout size={15} />
          </button>
        </div>
      </aside>

      {open ? <div className="scrim" onClick={() => setOpen(false)} /> : null}

      <div className="main">
        {/* Follows you onto every page. Turning the app off is the kind of
            thing that gets forgotten the moment you switch tabs, and the cost
            of forgetting is that nobody can use Advent Connect. */}
        {maintenance.active ? (
          <div className="maint-banner">
            <span className="pulse" />
            <span>The app is OFF for everyone — members see the maintenance screen.</span>
            {pathname !== "/maintenance" ? (
              <Link href="/maintenance">Turn it back on</Link>
            ) : null}
          </div>
        ) : null}

        <header className="topbar">
          <button
            className="btn ghost menu-btn"
            onClick={() => setOpen((v) => !v)}
            aria-label="Menu"
          >
            <IconMenu size={17} />
          </button>
          <div style={{ minWidth: 0 }}>
            <h1>{meta.title}</h1>
            {meta.sub ? <div className="topbar-sub truncate">{meta.sub}</div> : null}
          </div>
        </header>

        <main className="content" key={pathname}>
          {children}
        </main>
      </div>
    </div>
  );
}
