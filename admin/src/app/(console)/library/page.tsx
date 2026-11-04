"use client";

import { useCallback, useState } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { supabase } from "@/lib/supabase";
import { useAsync } from "@/lib/useAsync";
import { useSession } from "@/lib/session";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import { ErrorBox, Note, PageHead, Segmented, TableSkeleton } from "@/components/ui";
import { truncate } from "@/lib/format";

/**
 * Library content (patch_315): the two hymnals, and the EGW books and music
 * the Library tab offers. Hymn edits reach members when they pull to refresh
 * the Hymnal (HymnService.refresh merges them over the bundled copy). Files
 * go to the public `library` storage bucket — upload needs a super admin.
 */
type Hymn = {
  id: number;
  collection: string;
  number: number;
  title: string;
  lyrics: string;
  category: string | null;
  is_published: boolean;
};

type Item = {
  id: number;
  kind: "egw_book" | "music";
  title: string;
  author: string | null;
  description: string | null;
  language: string | null;
  cover_url: string | null;
  file_url: string | null;
  epub_url: string | null;
  sort_order: number | null;
  is_published: boolean;
};

const TABS = ["sda_hymnal", "kristu_munzwiyo", "egw_book", "music"] as const;
type Tab = (typeof TABS)[number];
const TAB_LABELS: Record<Tab, string> = {
  sda_hymnal: "SDA Hymnal",
  kristu_munzwiyo: "Kristu MuNzwiyo",
  egw_book: "EGW books",
  music: "Music",
};

async function upload(file: File, folder: string): Promise<string> {
  const safe = file.name.replace(/[^A-Za-z0-9._-]/g, "_");
  const path = `${folder}/${Date.now()}-${safe}`;
  const { error } = await supabase().storage.from("library").upload(path, file, {
    upsert: false,
    contentType: file.type || undefined,
  });
  if (error) throw new Error(`Upload failed: ${error.message}`);
  return supabase().storage.from("library").getPublicUrl(path).data.publicUrl;
}

export default function LibraryPage() {
  const [tab, setTab] = useState<Tab>("sda_hymnal");
  const isHymns = tab === "sda_hymnal" || tab === "kristu_munzwiyo";
  return (
    <div>
      <PageHead title="Library" sub="Hymns, Ellen G. White books and music." />
      <div className="toolbar">
        <Segmented options={TABS} value={tab} onChange={setTab} labels={TAB_LABELS} />
      </div>
      {isHymns ? <HymnsEditor collection={tab} key={tab} /> : <ItemsEditor kind={tab as Item["kind"]} key={tab} />}
    </div>
  );
}

/* ---------------------------------------------------------------- hymns */

function HymnsEditor({ collection }: { collection: string }) {
  const toast = useToast();
  const ask = useAsk();
  const { can } = useSession();
  const [q, setQ] = useState("");
  const [applied, setApplied] = useState("");
  const load = useCallback(
    () => rpcList<Hymn>("admin_list_hymns", { p_collection: collection, p_search: applied || null }),
    [collection, applied],
  );
  const { data, error, loading, reload } = useAsync<Hymn[]>(load, [collection, applied]);
  const [form, setForm] = useState<(Omit<Hymn, "id"> & { id: number | null }) | null>(null);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    if (!form) return;
    setSaving(true);
    try {
      await rpc("admin_save_hymn", {
        p_id: form.id,
        p_collection: collection,
        p_number: form.number,
        p_title: form.title,
        p_lyrics: form.lyrics,
        p_category: form.category,
        p_is_published: form.is_published,
      });
      toast.ok("Saved. Members see it after pulling down to refresh the Hymnal.");
      setForm(null);
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Could not save.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <Note>
        Edits reach phones when members pull down to refresh the Hymnal. Hymn words belong to their
        publishers — only add hymns the app has permission to use.
      </Note>
      <form
        className="row toolbar"
        style={{ gap: 8 }}
        onSubmit={(e) => {
          e.preventDefault();
          setApplied(q.trim());
        }}
      >
        <input className="input" style={{ maxWidth: 280 }} placeholder="Number or title…" value={q} onChange={(e) => setQ(e.target.value)} />
        <button className="btn ghost" type="submit">Search</button>
        {can("manager") ? (
          <button
            type="button"
            className="btn primary"
            onClick={() =>
              setForm({ id: null, collection, number: (data?.length ?? 0) + 1, title: "", lyrics: "", category: "", is_published: true })
            }
          >
            New hymn
          </button>
        ) : null}
      </form>

      {form ? (
        <section className="card" style={{ padding: 18, margin: "12px 0 18px" }}>
          <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
            <input
              className="input"
              style={{ width: 90 }}
              inputMode="numeric"
              value={form.number || ""}
              placeholder="No."
              onChange={(e) => setForm({ ...form, number: Number(e.target.value.replace(/\D/g, "")) })}
            />
            <input className="input" style={{ flex: 1, minWidth: 200 }} placeholder="Title" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
            <input className="input" style={{ maxWidth: 200 }} placeholder="Category" value={form.category ?? ""} onChange={(e) => setForm({ ...form, category: e.target.value })} />
            <label className="row" style={{ gap: 6 }}>
              <input type="checkbox" checked={form.is_published} onChange={(e) => setForm({ ...form, is_published: e.target.checked })} />
              Published
            </label>
          </div>
          <textarea
            className="input"
            rows={14}
            style={{ width: "100%", marginTop: 8, fontFamily: "inherit" }}
            placeholder="Words — a blank line between verses"
            value={form.lyrics}
            onChange={(e) => setForm({ ...form, lyrics: e.target.value })}
          />
          <div className="actions" style={{ marginTop: 10 }}>
            <button className="btn primary" onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</button>
            <button className="btn ghost" onClick={() => setForm(null)}>Cancel</button>
          </div>
        </section>
      ) : null}

      {error ? <ErrorBox message={error} /> : null}
      {loading && !data ? (
        <TableSkeleton rows={8} cols={2} />
      ) : (
        <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1 }}>
          <table>
            <thead>
              <tr>
                <th>Hymn</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {(data ?? []).map((h) => (
                <tr key={h.id}>
                  <td>
                    <b>
                      {h.number}. {h.title}
                    </b>
                    {!h.is_published ? <span className="chip grey"> HIDDEN</span> : null}
                    <div className="meta">{truncate(h.lyrics.replace(/\s+/g, " "), 140)}</div>
                  </td>
                  <td className="nowrap">
                    <div className="actions">
                      {can("manager") ? (
                        <button className="btn ghost sm" onClick={() => setForm({ ...h })}>Edit</button>
                      ) : null}
                      {can("owner") ? (
                        <button
                          className="btn red sm"
                          onClick={async () => {
                            const ok = await ask({
                              title: `Delete hymn ${h.number}?`,
                              sub: "Hiding it (Edit → untick Published) keeps it recoverable. Delete only a duplicate or a mistake.",
                              confirmLabel: "Delete",
                              tone: "red",
                            });
                            if (ok === null) return;
                            try {
                              await rpc("admin_delete_hymn", { p_id: h.id });
                              toast.ok("Deleted.");
                              reload();
                            } catch (e) {
                              toast.err(e instanceof Error ? e.message : "Could not delete.");
                            }
                          }}
                        >
                          Delete
                        </button>
                      ) : null}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

/* --------------------------------------------------- books and music */

const EMPTY_ITEM = (kind: Item["kind"]): Omit<Item, "id"> & { id: number | null } => ({
  id: null,
  kind,
  title: "",
  author: kind === "egw_book" ? "Ellen G. White" : "",
  description: "",
  language: "English",
  cover_url: "",
  file_url: "",
  epub_url: "",
  sort_order: null,
  is_published: true,
});

function ItemsEditor({ kind }: { kind: Item["kind"] }) {
  const toast = useToast();
  const ask = useAsk();
  const { can } = useSession();
  const load = useCallback(() => rpcList<Item>("admin_list_library_items", { p_kind: kind }), [kind]);
  const { data, error, loading, reload } = useAsync<Item[]>(load, [kind]);
  const [form, setForm] = useState<ReturnType<typeof EMPTY_ITEM> | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const pick = async (field: "file_url" | "epub_url" | "cover_url", file: File | undefined) => {
    if (!file || !form) return;
    setBusy(field);
    try {
      const url = await upload(file, field === "cover_url" ? "covers" : kind);
      setForm({ ...form, [field]: url });
      toast.ok("Uploaded.");
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Upload failed.");
    } finally {
      setBusy(null);
    }
  };

  const save = async () => {
    if (!form) return;
    setBusy("save");
    try {
      await rpc("admin_save_library_item", {
        p_id: form.id,
        p_kind: kind,
        p_title: form.title,
        p_author: form.author,
        p_description: form.description,
        p_language: form.language,
        p_cover_url: form.cover_url,
        p_file_url: form.file_url,
        p_epub_url: form.epub_url,
        p_sort_order: form.sort_order,
        p_is_published: form.is_published,
      });
      toast.ok("Saved — it shows in the Library.");
      setForm(null);
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Could not save.");
    } finally {
      setBusy(null);
    }
  };

  const fileLabel = kind === "music" ? "Audio file (MP3)" : "Book file (PDF)";

  return (
    <div>
      {can("manager") ? (
        <div className="toolbar">
          <button className="btn primary" onClick={() => setForm(EMPTY_ITEM(kind))}>
            {kind === "music" ? "Add music" : "Add book"}
          </button>
        </div>
      ) : null}

      {form ? (
        <section className="card" style={{ padding: 18, margin: "12px 0 18px" }}>
          <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
            <input className="input" style={{ flex: 1, minWidth: 220 }} placeholder="Title" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
            <input className="input" style={{ maxWidth: 200 }} placeholder="Author / artist" value={form.author ?? ""} onChange={(e) => setForm({ ...form, author: e.target.value })} />
            <input className="input" style={{ maxWidth: 140 }} placeholder="Language" value={form.language ?? ""} onChange={(e) => setForm({ ...form, language: e.target.value })} />
            <input
              className="input"
              style={{ width: 90 }}
              placeholder="Order"
              inputMode="numeric"
              value={form.sort_order ?? ""}
              onChange={(e) => setForm({ ...form, sort_order: e.target.value ? Number(e.target.value.replace(/\D/g, "")) : null })}
            />
          </div>
          <textarea className="input" rows={2} style={{ width: "100%", marginTop: 8 }} placeholder="Short description" value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} />
          {(
            [
              ["file_url", fileLabel, kind === "music" ? "audio/*" : "application/pdf"],
              ...(kind === "egw_book" ? [["epub_url", "EPUB (optional, better reading)", ".epub,application/epub+zip"]] : []),
              ["cover_url", "Cover image", "image/*"],
            ] as [("file_url" | "epub_url" | "cover_url"), string, string][]
          ).map(([field, label, accept]) => (
            <div key={field} className="row" style={{ gap: 8, marginTop: 8, flexWrap: "wrap" }}>
              <span style={{ width: 210 }}>{label}</span>
              <input type="file" accept={accept} disabled={busy !== null} onChange={(e) => pick(field, e.target.files?.[0])} />
              <span className="meta">{busy === field ? "Uploading…" : form[field] ? "✓ uploaded" : "—"}</span>
            </div>
          ))}
          <label className="row" style={{ gap: 6, marginTop: 8 }}>
            <input type="checkbox" checked={form.is_published} onChange={(e) => setForm({ ...form, is_published: e.target.checked })} />
            Published
          </label>
          <div className="actions" style={{ marginTop: 10 }}>
            <button className="btn primary" onClick={save} disabled={busy !== null}>{busy === "save" ? "Saving…" : "Save"}</button>
            <button className="btn ghost" onClick={() => setForm(null)}>Cancel</button>
          </div>
        </section>
      ) : null}

      {error ? <ErrorBox message={error} /> : null}
      {loading && !data ? (
        <TableSkeleton rows={6} cols={2} />
      ) : (
        <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1 }}>
          <table>
            <thead>
              <tr>
                <th>{kind === "music" ? "Music" : "Book"}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {(data ?? []).map((it) => (
                <tr key={it.id}>
                  <td>
                    <b>{it.title}</b>
                    {!it.is_published ? <span className="chip grey"> HIDDEN</span> : null}
                    <div className="meta">{[it.author, it.language].filter(Boolean).join(" · ")}</div>
                  </td>
                  <td className="nowrap">
                    <div className="actions">
                      {can("manager") ? (
                        <button
                          className="btn ghost sm"
                          onClick={() =>
                            setForm({
                              ...it,
                              author: it.author ?? "",
                              description: it.description ?? "",
                              language: it.language ?? "",
                              cover_url: it.cover_url ?? "",
                              file_url: it.file_url ?? "",
                              epub_url: it.epub_url ?? "",
                            })
                          }
                        >
                          Edit
                        </button>
                      ) : null}
                      {can("owner") ? (
                        <button
                          className="btn red sm"
                          onClick={async () => {
                            const ok = await ask({
                              title: `Delete “${it.title}”?`,
                              sub: "It disappears from every member's Library. Hiding it (Edit → untick Published) is reversible.",
                              confirmLabel: "Delete",
                              tone: "red",
                            });
                            if (ok === null) return;
                            try {
                              await rpc("admin_delete_library_item", { p_id: it.id });
                              toast.ok("Deleted.");
                              reload();
                            } catch (e) {
                              toast.err(e instanceof Error ? e.message : "Could not delete.");
                            }
                          }}
                        >
                          Delete
                        </button>
                      ) : null}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
