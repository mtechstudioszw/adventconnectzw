"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { supabase } from "@/lib/supabase";
import { useAsync } from "@/lib/useAsync";
import { useSession } from "@/lib/session";
import { useToast } from "@/components/Toast";
import { ErrorBox, Note, PageHead, Segmented, TableSkeleton } from "@/components/ui";
import { IconRefresh } from "@/components/icons";

/**
 * Hymn matching (patch_314): each Kristu MuNzwiyo (Christ in Song, Shona)
 * hymn → the same song's number in the SDA Hymnal. The app's "Also in"
 * switch inside a hymn (HymnLinkService) shows only where a match exists, so
 * until this table is filled nobody can flip a hymn between Shona and
 * English. The two books are numbered differently — never guess a match;
 * a wrong one sends a congregation to the wrong hymn.
 */
type Row = {
  cis_number: number;
  cis_title: string;
  sda_number: number | null;
  sda_title: string | null;
};

const VIEWS = ["all", "unmatched", "matched"] as const;
type View = (typeof VIEWS)[number];

export default function HymnsPage() {
  const toast = useToast();
  const { can } = useSession();
  const canEdit = can("manager");

  const load = useCallback(() => rpcList<Row>("admin_list_hymn_links"), []);
  const { data, error, loading, reload } = useAsync<Row[]>(load, []);

  // Every SDA Hymnal title, so a typed number shows its title before saving.
  const [sdaTitles, setSdaTitles] = useState<Record<number, string>>({});
  useEffect(() => {
    supabase()
      .from("hymns")
      .select("number,title")
      .eq("collection", "sda_hymnal")
      .then(({ data: rows }) => {
        const m: Record<number, string> = {};
        for (const r of (rows ?? []) as { number: number; title: string }[]) m[r.number] = r.title;
        setSdaTitles(m);
      });
  }, []);

  const [edits, setEdits] = useState<Record<number, string>>({});
  const [view, setView] = useState<View>("all");
  const [q, setQ] = useState("");
  const [paste, setPaste] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const rows = data ?? [];
  const valueOf = (r: Row) =>
    r.cis_number in edits ? edits[r.cis_number] : r.sda_number ? String(r.sda_number) : "";

  const changed = useMemo(
    () =>
      rows.filter((r) => {
        if (!(r.cis_number in edits)) return false;
        const now = edits[r.cis_number].trim();
        return now !== (r.sda_number ? String(r.sda_number) : "");
      }),
    [rows, edits],
  );

  const matchedCount = rows.filter((r) => valueOf(r).trim() !== "").length;

  const visible = rows.filter((r) => {
    const v = valueOf(r).trim();
    if (view === "unmatched" && v) return false;
    if (view === "matched" && !v) return false;
    if (!q) return true;
    const s = q.toLowerCase();
    return String(r.cis_number) === s || r.cis_title.toLowerCase().includes(s);
  });

  const applyPaste = () => {
    // One pair per line: "<Kristu MuNzwiyo number> <SDA number>", any
    // separator. "0" or "-" clears that hymn's match.
    const next = { ...edits };
    let n = 0;
    for (const line of paste.split(/\r?\n/)) {
      const m = line.trim().match(/^(\d{1,4})\D+(\d{1,4}|-)$/);
      if (!m) continue;
      const cis = Number(m[1]);
      if (!rows.some((r) => r.cis_number === cis)) continue;
      next[cis] = m[2] === "-" || m[2] === "0" ? "" : m[2];
      n++;
    }
    setEdits(next);
    toast.info(n ? `${n} matches filled in — review them, then Save.` : "No lines like “12 410” found.");
  };

  const save = async () => {
    setSaving(true);
    setSaveError(null);
    try {
      const payload = changed.map((r) => {
        const v = edits[r.cis_number].trim();
        return { cis: r.cis_number, sda: v ? Number(v) : null };
      });
      const n = await rpc<number>("admin_set_hymn_links", { p_links: payload });
      toast.ok(`${n} hymn matches saved. Phones pick them up on their next refresh.`);
      setEdits({});
      reload();
    } catch (e) {
      const m = e instanceof Error ? e.message : "Could not save.";
      setSaveError(m);
      toast.err(m);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <PageHead
        title="Hymn matching"
        sub={`Kristu MuNzwiyo → SDA Hymnal. ${matchedCount} of ${rows.length} matched.`}
        actions={
          <>
            <button className="btn ghost" onClick={reload} disabled={loading}>
              <IconRefresh className="btn-icon" size={15} />
              Refresh
            </button>
            {canEdit ? (
              <button className="btn primary" onClick={save} disabled={saving || changed.length === 0}>
                {saving ? "Saving…" : `Save ${changed.length || ""}`.trim()}
              </button>
            ) : null}
          </>
        }
      />

      <Note>
        A match turns on the <b>“Also in”</b> switch inside that hymn in the app, so members can
        flip between Shona and English. Only enter a match you are sure of — check the words, not
        just the title. Leave it empty when the hymn is not in the SDA Hymnal.
      </Note>

      {saveError ? <ErrorBox message={saveError} /> : null}
      {error ? <ErrorBox message={error} /> : null}

      <div className="toolbar row" style={{ gap: 8, flexWrap: "wrap" }}>
        <Segmented
          options={VIEWS}
          value={view}
          onChange={setView}
          labels={{ all: "All", unmatched: "Not matched", matched: "Matched" }}
        />
        <input
          className="input"
          style={{ maxWidth: 260 }}
          placeholder="Number or Shona title…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
      </div>

      {canEdit ? (
        <details style={{ margin: "8px 0 14px" }}>
          <summary className="meta" style={{ cursor: "pointer" }}>
            Paste many at once (from a printed cross-reference list)
          </summary>
          <textarea
            className="input"
            rows={6}
            style={{ width: "100%", marginTop: 8, fontFamily: "monospace" }}
            placeholder={"One per line: Kristu MuNzwiyo number, then SDA Hymnal number\n1 612\n2 341\n3 -   (dash = no match)"}
            value={paste}
            onChange={(e) => setPaste(e.target.value)}
          />
          <button className="btn ghost sm" style={{ marginTop: 6 }} onClick={applyPaste}>
            Fill in
          </button>
        </details>
      ) : null}

      {loading && !data ? (
        <TableSkeleton rows={8} cols={3} />
      ) : (
        <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1 }}>
          <table>
            <thead>
              <tr>
                <th>Kristu MuNzwiyo</th>
                <th style={{ width: 120 }}>SDA Hymnal no.</th>
                <th>SDA Hymnal title</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((r) => {
                const v = valueOf(r).trim();
                const n = v ? Number(v) : null;
                const title = n ? sdaTitles[n] ?? (n === r.sda_number ? r.sda_title : null) : null;
                const invalid = !!v && (!/^\d+$/.test(v) || n! < 1 || n! > 695);
                const isChanged = r.cis_number in edits && v !== (r.sda_number ? String(r.sda_number) : "");
                return (
                  <tr key={r.cis_number}>
                    <td>
                      <b>{r.cis_number}.</b> {r.cis_title}
                    </td>
                    <td>
                      <input
                        className="input"
                        inputMode="numeric"
                        disabled={!canEdit}
                        style={{
                          width: 90,
                          borderColor: invalid ? "var(--red, #D32F2F)" : isChanged ? "var(--blue, #1565C0)" : undefined,
                        }}
                        value={valueOf(r)}
                        placeholder="—"
                        onChange={(e) => setEdits({ ...edits, [r.cis_number]: e.target.value.replace(/\D/g, "") })}
                      />
                    </td>
                    <td className={title ? "" : "faint"}>
                      {invalid ? "The SDA Hymnal has 695 hymns" : title ?? (v ? "…" : "Not matched")}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
