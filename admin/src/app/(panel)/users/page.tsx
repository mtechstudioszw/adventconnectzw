import { getServiceSupabase } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/admin";
import { revokeBusinessAction, setUserBannedAction } from "./actions";
import Link from "next/link";

type Filter = "all" | "business" | "banned";

type ProfileRow = {
  id: string;
  full_name: string | null;
  username: string | null;
  profile_photo_url: string | null;
  province: string | null;
  city: string | null;
  is_business: boolean;
  is_banned: boolean;
  is_verified: boolean;
  created_at: string;
  last_active_at: string | null;
};

async function fetchUsers(
  filter: Filter,
  search: string,
): Promise<ProfileRow[]> {
  const supabase = getServiceSupabase();
  let query = supabase
    .from("profiles")
    .select(
      "id, full_name, username, profile_photo_url, province, city, is_business, is_banned, is_verified, created_at, last_active_at",
    )
    .order("created_at", { ascending: false })
    .limit(100);

  if (filter === "business") query = query.eq("is_business", true);
  if (filter === "banned") query = query.eq("is_banned", true);

  const trimmed = search.trim();
  if (trimmed.length > 0) {
    const term = `%${trimmed}%`;
    query = query.or(`full_name.ilike.${term},username.ilike.${term}`);
  }

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data ?? []) as ProfileRow[];
}

export default async function UsersPage({
  searchParams,
}: {
  searchParams: { filter?: string; q?: string };
}) {
  await requireAdmin();
  const filter: Filter =
    searchParams.filter === "business" || searchParams.filter === "banned"
      ? (searchParams.filter as Filter)
      : "all";
  const search = searchParams.q ?? "";
  const users = await fetchUsers(filter, search);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold text-navy">Users</h1>
        <p className="text-sm text-ink/60 mt-1">
          Browse members. Banning prevents the user from posting, applying,
          and selling. Revoking business drops them back to personal mode.
        </p>
      </header>

      <SearchBar initial={search} filter={filter} />
      <FilterTabs current={filter} q={search} />

      {users.length === 0 ? (
        <div className="bg-white border border-ink/5 rounded-2xl p-10 text-center">
          <div className="text-4xl">🔍</div>
          <h3 className="font-bold text-navy mt-3">No users match</h3>
          <p className="text-sm text-ink/60 mt-1">
            Try a different filter or clear the search.
          </p>
        </div>
      ) : (
        <ul className="bg-white border border-ink/5 rounded-2xl divide-y divide-ink/5 overflow-hidden">
          {users.map((user) => (
            <UserRow key={user.id} user={user} />
          ))}
        </ul>
      )}
    </div>
  );
}

function SearchBar({ initial, filter }: { initial: string; filter: Filter }) {
  return (
    <form action="/users" method="get" className="flex gap-2">
      <input type="hidden" name="filter" value={filter} />
      <input
        type="text"
        name="q"
        defaultValue={initial}
        placeholder="Search by name or username…"
        className="flex-1 px-4 py-2 rounded-xl border border-ink/10 bg-white focus:border-primary focus:outline-none text-sm"
      />
      <button
        type="submit"
        className="px-4 py-2 rounded-xl bg-primary text-white text-sm font-semibold hover:opacity-95"
      >
        Search
      </button>
    </form>
  );
}

function FilterTabs({ current, q }: { current: Filter; q: string }) {
  const tabs: { value: Filter; label: string }[] = [
    { value: "all", label: "All users" },
    { value: "business", label: "Business" },
    { value: "banned", label: "Banned" },
  ];
  const qsuffix = q ? `&q=${encodeURIComponent(q)}` : "";
  return (
    <div className="flex gap-2 border-b border-ink/10">
      {tabs.map((tab) => (
        <Link
          key={tab.value}
          href={`/users?filter=${tab.value}${qsuffix}`}
          className={`px-4 py-2 text-sm font-semibold border-b-2 -mb-px transition-colors ${
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

function UserRow({ user }: { user: ProfileRow }) {
  const name = user.full_name?.trim() || "(no name)";
  const initial = name.slice(0, 1).toUpperCase();
  const where = [user.city, user.province].filter(Boolean).join(", ");
  const joined = new Date(user.created_at).toLocaleDateString();
  const lastActive = user.last_active_at
    ? new Date(user.last_active_at).toLocaleDateString()
    : "—";

  return (
    <li className="p-4 flex items-center gap-4">
      <div className="w-10 h-10 rounded-full bg-primary text-white grid place-items-center font-bold overflow-hidden shrink-0">
        {user.profile_photo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={user.profile_photo_url}
            alt={name}
            className="w-full h-full object-cover"
          />
        ) : (
          initial
        )}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex flex-wrap items-baseline gap-x-2">
          <span className="font-semibold text-navy truncate">{name}</span>
          {user.username && (
            <span className="text-xs text-ink/55">@{user.username}</span>
          )}
          {user.is_business && (
            <span className="text-[10px] font-bold uppercase tracking-wider bg-primary/10 text-primary px-1.5 py-0.5 rounded">
              Business
            </span>
          )}
          {user.is_verified && (
            <span className="text-[10px] font-bold uppercase tracking-wider bg-gold/15 text-gold px-1.5 py-0.5 rounded">
              Verified
            </span>
          )}
          {user.is_banned && (
            <span className="text-[10px] font-bold uppercase tracking-wider bg-warn/15 text-warn px-1.5 py-0.5 rounded">
              Banned
            </span>
          )}
        </div>
        <div className="text-xs text-ink/55 mt-0.5">
          {where || "—"} · joined {joined} · last active {lastActive}
        </div>
      </div>
      <div className="flex gap-2 shrink-0">
        {user.is_business && (
          <form
            action={async () => {
              "use server";
              await revokeBusinessAction(user.id);
            }}
          >
            <button
              type="submit"
              className="px-3 py-1.5 text-xs font-bold uppercase tracking-wider rounded-lg border border-ink/15 text-ink/75 hover:bg-ink/5"
            >
              Revoke business
            </button>
          </form>
        )}
        <form
          action={async () => {
            "use server";
            await setUserBannedAction(user.id, !user.is_banned);
          }}
        >
          <button
            type="submit"
            className={`px-3 py-1.5 text-xs font-bold uppercase tracking-wider rounded-lg ${
              user.is_banned
                ? "bg-ok text-white hover:opacity-95"
                : "border border-warn/40 text-warn hover:bg-warn/10"
            }`}
          >
            {user.is_banned ? "Unban" : "Ban"}
          </button>
        </form>
      </div>
    </li>
  );
}
