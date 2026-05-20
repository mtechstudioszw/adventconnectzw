"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { getBrowserSupabase } from "@/lib/supabase/browser";

type Item = { href: string; label: string; icon: string };

const items: Item[] = [
  { href: "/", label: "Dashboard", icon: "📊" },
  { href: "/applications", label: "Business apps", icon: "💼" },
  { href: "/users", label: "Users", icon: "👥" },
  { href: "/reports", label: "Reports", icon: "🛡️" },
  { href: "/feedback", label: "Feedback", icon: "💬" },
  { href: "/announcements", label: "Announcements", icon: "📣" },
];

export default function Sidebar({ email }: { email: string }) {
  const pathname = usePathname();
  const router = useRouter();

  const handleSignOut = async () => {
    const supabase = getBrowserSupabase();
    await supabase.auth.signOut();
    router.replace("/login");
  };

  return (
    <aside className="w-60 shrink-0 bg-navy text-white flex flex-col h-screen sticky top-0">
      <div className="px-5 pt-6 pb-5 border-b border-white/10">
        <div className="flex items-center gap-2">
          <div className="w-9 h-9 rounded-xl bg-white text-navy grid place-items-center font-bold">
            AC
          </div>
          <div>
            <div className="text-sm font-bold leading-tight">Admin panel</div>
            <div className="text-[11px] text-white/60">
              Advent Connect ZW
            </div>
          </div>
        </div>
      </div>
      <nav className="flex-1 p-3 space-y-1">
        {items.map((item) => {
          const active =
            item.href === "/"
              ? pathname === "/"
              : pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                active
                  ? "bg-white text-navy"
                  : "text-white/80 hover:bg-white/10"
              }`}
            >
              <span className="text-base leading-none">{item.icon}</span>
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>
      <div className="p-3 border-t border-white/10 space-y-2">
        <div className="px-2 text-[11px] text-white/60 leading-tight">
          Signed in as
          <div className="text-white/90 text-xs font-medium truncate">
            {email}
          </div>
        </div>
        <button
          onClick={handleSignOut}
          className="w-full text-left px-3 py-2 rounded-lg text-xs text-white/80 hover:bg-white/10"
        >
          Sign out
        </button>
      </div>
    </aside>
  );
}
