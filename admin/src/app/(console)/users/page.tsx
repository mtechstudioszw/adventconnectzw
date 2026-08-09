"use client";

import { useState } from "react";
import { rpc } from "@/lib/rpc";
import { Queue } from "@/components/Queue";
import { BusyButton } from "@/components/ui";
import { fmtDay } from "@/lib/format";
import { useSession } from "@/lib/session";

type Member = {
  id: string;
  full_name: string;
  email: string | null;
  created_at: string;
  is_banned: boolean;
  is_super_admin: boolean;
};

export default function UsersPage() {
  const [query, setQuery] = useState("");
  const [applied, setApplied] = useState("");
  const { can } = useSession();
  const seesPii = can("manager");
  const canBan = can("owner");

  return (
    <Queue<Member>
      rpcName="admin_search_users"
      rpcArgs={{ p_query: applied }}
      title="Members"
      sub={
        canBan
          ? "Search the membership. You can send someone a direct notice, or ban them."
          : "Search the membership. Banning is an owner-only action."
      }
      columns={["Name", seesPii ? "Email" : "Joined", "Status", ""]}
      emptyTitle="No members matched"
      emptySub={applied ? "Try a different name or email." : "Type a name to search."}
      toolbar={
        <form
          className="row"
          style={{ gap: 8 }}
          onSubmit={(e) => {
            e.preventDefault();
            setApplied(query.trim());
          }}
        >
          <input
            className="input"
            style={{ maxWidth: 300 }}
            placeholder="Search name or email…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <button className="btn primary" type="submit">
            Search
          </button>
        </form>
      }
      row={(u, { act, ask }) => (
        <tr key={u.id}>
          <td>
            <b>{u.full_name}</b>
            {u.is_super_admin ? <span className="chip gold"> ADMIN</span> : null}
            {!seesPii ? <div className="meta">Joined {fmtDay(u.created_at)}</div> : null}
          </td>
          <td>
            {seesPii ? (
              <>
                {u.email ?? "—"}
                <div className="meta">Joined {fmtDay(u.created_at)}</div>
              </>
            ) : (
              <span className="faint">Hidden at your role</span>
            )}
          </td>
          <td>
            <span className={`chip ${u.is_banned ? "red" : "green"}`}>
              {u.is_banned ? "BANNED" : "ACTIVE"}
            </span>
          </td>
          <td className="nowrap">
            <div className="actions">
              <BusyButton
                className="btn ghost sm"
                onClick={async () => {
                  const title = await ask({
                    title: `Notify ${u.full_name}`,
                    sub: "Step 1 of 2 — the notification title.",
                    input: { placeholder: "e.g. A note from the Advent Connect team", required: true },
                    confirmLabel: "Next",
                  });
                  if (!title) return;
                  const body = await ask({
                    title: `Notify ${u.full_name}`,
                    sub: "Step 2 of 2 — the message.",
                    input: { placeholder: "Write the message…", multiline: true, required: true },
                    confirmLabel: "Send",
                  });
                  if (!body) return;
                  await act(async () => {
                    const n = await rpc<number>("admin_notify_user", {
                      p_user_id: u.id,
                      p_title: title,
                      p_body: body,
                    });
                    if (!n) throw new Error("That account could not be found.");
                  }, "Sent — it lands in their notifications.");
                }}
              >
                Notify
              </BusyButton>

              {/* A super admin cannot be banned from here. Locking the only
                  person who can undo it out of their own app is not an action
                  worth offering. */}
              {u.is_super_admin || !canBan ? null : u.is_banned ? (
                <BusyButton
                  className="btn ghost sm"
                  onClick={() =>
                    act(
                      () => rpc("admin_set_banned", { p_user_id: u.id, p_banned: false }),
                      `${u.full_name} can use the app again.`,
                    )
                  }
                >
                  Unban
                </BusyButton>
              ) : (
                <BusyButton
                  className="btn red sm"
                  onClick={async () => {
                    const ok = await ask({
                      title: `Ban ${u.full_name}?`,
                      sub: "They are notified and blocked from posting, messaging and selling. You can undo this.",
                      confirmLabel: "Ban",
                      tone: "red",
                    });
                    if (ok === null) return;
                    await act(
                      () => rpc("admin_set_banned", { p_user_id: u.id, p_banned: true }),
                      `${u.full_name} is banned.`,
                    );
                  }}
                >
                  Ban
                </BusyButton>
              )}
            </div>
          </td>
        </tr>
      )}
      deps={[seesPii, canBan]}
    />
  );
}
