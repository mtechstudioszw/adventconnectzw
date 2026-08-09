"use client";

import { useCallback, useState } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useAsk } from "@/components/Dialog";
import { useToast } from "@/components/Toast";
import {
  BusyButton,
  Empty,
  ErrorBox,
  Note,
  PageHead,
  TableSkeleton,
} from "@/components/ui";
import { IconCrown, IconRefresh } from "@/components/icons";
import { fmtDay } from "@/lib/format";
import { ROLES, ROLE_BLURB, useSession, type Role } from "@/lib/session";

type StaffRow = {
  user_id: string;
  full_name: string | null;
  email: string | null;
  role: Role;
  added_at: string;
  disabled: boolean;
};

type Candidate = {
  id: string;
  full_name: string;
  email: string | null;
};

export default function StaffPage() {
  const { role: myRole, email: myEmail } = useSession();
  const ask = useAsk();
  const toast = useToast();
  const [query, setQuery] = useState("");
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [searching, setSearching] = useState(false);

  const load = useCallback(() => rpcList<StaffRow>("admin_list_staff"), []);
  const { data, error, loading, reload } = useAsync(load, []);
  const staff = data ?? [];

  const owners = staff.filter((s) => s.role === "owner" && !s.disabled).length;

  if (myRole !== "owner") {
    return (
      <div>
        <PageHead title="Staff & roles" />
        <Note>
          Only an <strong>owner</strong> can see and change who works in this
          console.
        </Note>
      </div>
    );
  }

  const setRole = async (userId: string, name: string, next: Role | "none") => {
    try {
      await rpc("admin_set_staff_role", {
        p_user: userId,
        p_role: next === "none" ? null : next,
      });
      toast.ok(
        next === "none" ? `${name} no longer has console access.` : `${name} is now ${next}.`,
      );
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Could not change that role.");
    }
  };

  const search = async () => {
    const q = query.trim();
    if (!q) return;
    setSearching(true);
    try {
      const rows = await rpcList<Candidate>("admin_search_users", { p_query: q });
      setCandidates(rows);
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Search failed.");
    } finally {
      setSearching(false);
    }
  };

  const existing = new Set(staff.map((s) => s.user_id));

  return (
    <div className="stack">
      <PageHead
        title="Staff & roles"
        sub="Who can work in this console, and how much of it they can touch."
        actions={
          <button className="btn ghost" onClick={reload} disabled={loading}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />

      {error ? <ErrorBox message={error} /> : null}

      <div className="card card-pad">
        <div className="section-title">What each role can do</div>
        <div style={{ display: "grid", gap: 10 }}>
          {ROLES.map((r) => (
            <div className="row" key={r} style={{ alignItems: "flex-start", gap: 12 }}>
              <span className={`chip ${r === "owner" ? "gold" : "blue"}`} style={{ minWidth: 82 }}>
                {r}
              </span>
              <span className="meta">{ROLE_BLURB[r]}</span>
            </div>
          ))}
        </div>
      </div>

      <section>
        <div className="section-title">
          Current staff
          {staff.length > 0 ? <span className="count">{staff.length}</span> : null}
        </div>

        {loading && !data ? (
          <TableSkeleton rows={2} cols={4} />
        ) : staff.length === 0 ? (
          <Empty title="No staff yet" sub="Search below to give someone a role." />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Person</th>
                  <th>Role</th>
                  <th>Since</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {staff.map((s) => {
                  const isMe = !!myEmail && s.email?.toLowerCase() === myEmail.toLowerCase();
                  const lastOwner = s.role === "owner" && owners <= 1;
                  return (
                    <tr key={s.user_id}>
                      <td>
                        <b>{s.full_name ?? "—"}</b>
                        {isMe ? <span className="chip blue"> YOU</span> : null}
                        <div className="meta">{s.email ?? "—"}</div>
                      </td>
                      <td>
                        <span className={`chip ${s.role === "owner" ? "gold" : "blue"}`}>
                          {s.role}
                        </span>
                        {s.disabled ? <div className="meta">disabled</div> : null}
                      </td>
                      <td className="meta">{fmtDay(s.added_at)}</td>
                      <td className="nowrap">
                        <div className="actions">
                          <select
                            className="select"
                            style={{ width: 132 }}
                            value={s.role}
                            disabled={lastOwner}
                            title={
                              lastOwner
                                ? "This is the last owner. Promote someone else first."
                                : undefined
                            }
                            onChange={async (e) => {
                              const next = e.target.value as Role;
                              if (next === s.role) return;
                              const ok = await ask({
                                title: `Make ${s.full_name ?? "this person"} ${next}?`,
                                sub: ROLE_BLURB[next],
                                confirmLabel: "Change role",
                                tone: next === "owner" ? "red" : "primary",
                                typeToConfirm: next === "owner" ? "OWNER" : undefined,
                              });
                              if (ok === null) {
                                e.target.value = s.role;
                                return;
                              }
                              await setRole(s.user_id, s.full_name ?? "They", next);
                            }}
                          >
                            {ROLES.map((r) => (
                              <option key={r} value={r}>
                                {r}
                              </option>
                            ))}
                          </select>
                          <BusyButton
                            className="btn red sm"
                            disabled={lastOwner}
                            title={
                              lastOwner
                                ? "You cannot remove the last owner — nobody could get back in."
                                : undefined
                            }
                            onClick={async () => {
                              const ok = await ask({
                                title: `Remove ${s.full_name ?? "this person"}?`,
                                sub: "They lose access to this console immediately. Their Advent Connect account is untouched.",
                                confirmLabel: "Remove access",
                                tone: "red",
                              });
                              if (ok === null) return;
                              await setRole(s.user_id, s.full_name ?? "They", "none");
                            }}
                          >
                            Remove
                          </BusyButton>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {owners <= 1 ? (
          <div style={{ marginTop: 12 }}>
            <Note>
              <strong>You are the only owner.</strong> The console refuses to
              demote the last one on purpose — without that guard, one click
              locks everybody out permanently, and there is no way back in from
              the app. Consider adding a second owner you trust.
            </Note>
          </div>
        ) : null}
      </section>

      <section>
        <div className="section-title">Give someone a role</div>
        <div className="card card-pad">
          <form
            className="row"
            style={{ gap: 8, flexWrap: "wrap" }}
            onSubmit={(e) => {
              e.preventDefault();
              void search();
            }}
          >
            <input
              className="input"
              style={{ maxWidth: 320 }}
              placeholder="Search members by name or email…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
            <button className="btn primary" type="submit" disabled={searching || !query.trim()}>
              {searching ? <span className="spinner" /> : null}
              Search
            </button>
          </form>

          {candidates ? (
            candidates.length === 0 ? (
              <div className="meta" style={{ marginTop: 14 }}>
                Nobody matched that.
              </div>
            ) : (
              <div style={{ marginTop: 14, display: "grid", gap: 8 }}>
                {candidates.map((c) => {
                  const already = existing.has(c.id);
                  return (
                    <div
                      className="row"
                      key={c.id}
                      style={{
                        padding: "10px 12px",
                        border: "1px solid var(--border)",
                        borderRadius: 10,
                      }}
                    >
                      <div style={{ minWidth: 0, flex: 1 }}>
                        <b style={{ fontSize: 13 }}>{c.full_name}</b>
                        <div className="meta truncate">{c.email ?? "—"}</div>
                      </div>
                      {already ? (
                        <span className="chip grey">Already staff</span>
                      ) : (
                        <div className="actions">
                          {(["viewer", "moderator", "manager"] as const).map((r) => (
                            <BusyButton
                              key={r}
                              className="btn sm"
                              onClick={async () => {
                                const ok = await ask({
                                  title: `Make ${c.full_name} a ${r}?`,
                                  sub: ROLE_BLURB[r],
                                  confirmLabel: "Grant role",
                                });
                                if (ok === null) return;
                                await setRole(c.id, c.full_name, r);
                                setCandidates(null);
                                setQuery("");
                              }}
                            >
                              {r}
                            </BusyButton>
                          ))}
                          <BusyButton
                            className="btn red sm"
                            onClick={async () => {
                              const ok = await ask({
                                title: `Make ${c.full_name} an OWNER?`,
                                sub: "An owner can ban members, broadcast to everyone, take the app offline and change staff roles — including yours.",
                                confirmLabel: "Make owner",
                                tone: "red",
                                typeToConfirm: "OWNER",
                              });
                              if (ok === null) return;
                              await setRole(c.id, c.full_name, "owner");
                              setCandidates(null);
                              setQuery("");
                            }}
                          >
                            <IconCrown size={14} />
                            owner
                          </BusyButton>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )
          ) : null}
        </div>
      </section>

      <Note>
        Every role change is written to the audit log with your name against it.
      </Note>
    </div>
  );
}
