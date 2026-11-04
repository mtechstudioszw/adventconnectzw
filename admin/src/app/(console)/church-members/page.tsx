"use client";

import { useState } from "react";
import { rpcList } from "@/lib/rpc";
import { supabase } from "@/lib/supabase";
import { useToast } from "@/components/Toast";
import { Empty, ErrorBox, PageHead, TableSkeleton } from "@/components/ui";
import { fmtDay } from "@/lib/format";

/**
 * Who has a church as their home church (church_member_list — the church's
 * approved admin or a super admin). Read-only: membership is the member's
 * own choice in the app.
 */
type Church = { id: number; name: string; city: string | null };
type Member = { user_id: string; full_name: string; profile_photo_url: string | null; joined_at: string | null };

export default function ChurchMembersPage() {
  const toast = useToast();
  const [q, setQ] = useState("");
  const [churches, setChurches] = useState<Church[]>([]);
  const [picked, setPicked] = useState<Church | null>(null);
  const [members, setMembers] = useState<Member[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const search = async () => {
    const term = q.trim();
    if (term.length < 2) return;
    const { data, error: e } = await supabase()
      .from("churches")
      .select("id,name,city")
      .ilike("name", `%${term}%`)
      .order("name")
      .limit(25);
    if (e) toast.err("Could not search churches.");
    setChurches((data ?? []) as Church[]);
  };

  const open = async (c: Church) => {
    setPicked(c);
    setMembers(null);
    setError(null);
    setLoading(true);
    try {
      setMembers(await rpcList<Member>("church_member_list", { p_church_id: c.id }));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load members.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <PageHead title="Church members" sub="Members who set a church as their home church." />
      <form
        className="row toolbar"
        style={{ gap: 8 }}
        onSubmit={(e) => {
          e.preventDefault();
          search();
        }}
      >
        <input
          className="input"
          style={{ maxWidth: 320 }}
          placeholder="Church name…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <button className="btn primary" type="submit">
          Search
        </button>
      </form>

      {churches.length ? (
        <div className="row" style={{ gap: 6, flexWrap: "wrap", margin: "10px 0 16px" }}>
          {churches.map((c) => (
            <button
              key={c.id}
              className={`btn sm ${picked?.id === c.id ? "primary" : "ghost"}`}
              onClick={() => open(c)}
            >
              {c.name}
              {c.city ? ` · ${c.city}` : ""}
            </button>
          ))}
        </div>
      ) : null}

      {error ? <ErrorBox message={error} /> : null}
      {picked ? (
        loading ? (
          <TableSkeleton rows={5} cols={2} />
        ) : members && members.length ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{members.length} members of {picked.name}</th>
                  <th>Home church since</th>
                </tr>
              </thead>
              <tbody>
                {members.map((m) => (
                  <tr key={m.user_id}>
                    <td>
                      <b>{m.full_name}</b>
                    </td>
                    <td>{m.joined_at ? fmtDay(m.joined_at) : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : members ? (
          <Empty title="No members yet" sub="Nobody has set this as their home church." />
        ) : null
      ) : null}
    </div>
  );
}
