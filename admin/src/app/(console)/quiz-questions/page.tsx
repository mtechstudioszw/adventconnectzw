"use client";

import { useCallback, useState } from "react";
import { rpc, rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useSession } from "@/lib/session";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import { ErrorBox, PageHead, TableSkeleton } from "@/components/ui";
import { truncate } from "@/lib/format";

/**
 * The quiz question bank (patch_315). Add, edit, publish/unpublish, delete.
 * Everything is checked again in the database (2–6 options, a marked answer,
 * a difficulty) and logged.
 */
type Question = {
  id: number;
  question: string;
  options: string[];
  correct_index: number;
  explanation: string | null;
  reference: string | null;
  category: string;
  difficulty: "easy" | "medium" | "hard";
  is_published: boolean;
};

const EMPTY: Omit<Question, "id"> & { id: number | null } = {
  id: null,
  question: "",
  options: ["", "", "", ""],
  correct_index: 0,
  explanation: "",
  reference: "",
  category: "",
  difficulty: "medium",
  is_published: true,
};

export default function QuizQuestionsPage() {
  const toast = useToast();
  const ask = useAsk();
  const { can } = useSession();
  const canEdit = can("manager");

  const [search, setSearch] = useState("");
  const [applied, setApplied] = useState("");
  const load = useCallback(
    () => rpcList<Question>("admin_list_quiz_questions", { p_search: applied || null, p_limit: 200 }),
    [applied],
  );
  const { data, error, loading, reload } = useAsync<Question[]>(load, [applied]);

  const [form, setForm] = useState<typeof EMPTY | null>(null);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    if (!form) return;
    setSaving(true);
    try {
      await rpc("admin_save_quiz_question", {
        p_id: form.id,
        p_question: form.question,
        p_options: form.options.map((o) => o.trim()).filter((o) => o !== ""),
        p_correct_index: form.correct_index,
        p_explanation: form.explanation,
        p_reference: form.reference,
        p_category: form.category,
        p_difficulty: form.difficulty,
        p_is_published: form.is_published,
      });
      toast.ok(form.id ? "Question updated." : "Question added.");
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
      <PageHead
        title="Quiz questions"
        sub={`${data?.length ?? 0} shown${applied ? ` for “${applied}”` : " (newest first)"}.`}
        actions={
          canEdit ? (
            <button className="btn primary" onClick={() => setForm({ ...EMPTY, options: ["", "", "", ""] })}>
              New question
            </button>
          ) : null
        }
      />

      <form
        className="row toolbar"
        style={{ gap: 8 }}
        onSubmit={(e) => {
          e.preventDefault();
          setApplied(search.trim());
        }}
      >
        <input
          className="input"
          style={{ maxWidth: 320 }}
          placeholder="Search words or question #…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button className="btn ghost" type="submit">
          Search
        </button>
      </form>

      {form ? (
        <section className="card" style={{ padding: 18, margin: "12px 0 18px" }}>
          <h3 style={{ fontSize: 15, fontWeight: 700, marginBottom: 10 }}>
            {form.id ? `Edit question #${form.id}` : "New question"}
          </h3>
          <textarea
            className="input"
            rows={2}
            style={{ width: "100%" }}
            placeholder="The question…"
            value={form.question}
            onChange={(e) => setForm({ ...form, question: e.target.value })}
          />
          <div className="meta" style={{ margin: "10px 0 4px" }}>
            Options — tick the correct one
          </div>
          {form.options.map((o, i) => (
            <div key={i} className="row" style={{ gap: 8, marginBottom: 6 }}>
              <input
                type="radio"
                name="correct"
                checked={form.correct_index === i}
                onChange={() => setForm({ ...form, correct_index: i })}
              />
              <input
                className="input"
                style={{ flex: 1 }}
                placeholder={`Option ${String.fromCharCode(65 + i)}`}
                value={o}
                onChange={(e) => {
                  const options = [...form.options];
                  options[i] = e.target.value;
                  setForm({ ...form, options });
                }}
              />
            </div>
          ))}
          <div className="row" style={{ gap: 8, flexWrap: "wrap", marginTop: 8 }}>
            <input
              className="input"
              style={{ maxWidth: 200 }}
              placeholder="Category (e.g. Prophecy)"
              value={form.category}
              onChange={(e) => setForm({ ...form, category: e.target.value })}
            />
            <select
              className="input"
              style={{ maxWidth: 140 }}
              value={form.difficulty}
              onChange={(e) => setForm({ ...form, difficulty: e.target.value as Question["difficulty"] })}
            >
              <option value="easy">Easy</option>
              <option value="medium">Medium</option>
              <option value="hard">Hard</option>
            </select>
            <input
              className="input"
              style={{ maxWidth: 200 }}
              placeholder="Reference (e.g. John 3:16)"
              value={form.reference ?? ""}
              onChange={(e) => setForm({ ...form, reference: e.target.value })}
            />
            <label className="row" style={{ gap: 6 }}>
              <input
                type="checkbox"
                checked={form.is_published}
                onChange={(e) => setForm({ ...form, is_published: e.target.checked })}
              />
              Published
            </label>
          </div>
          <textarea
            className="input"
            rows={2}
            style={{ width: "100%", marginTop: 8 }}
            placeholder="Explanation shown after answering (optional)"
            value={form.explanation ?? ""}
            onChange={(e) => setForm({ ...form, explanation: e.target.value })}
          />
          <div className="actions" style={{ marginTop: 10 }}>
            <button className="btn primary" onClick={save} disabled={saving}>
              {saving ? "Saving…" : "Save"}
            </button>
            <button className="btn ghost" onClick={() => setForm(null)}>
              Cancel
            </button>
          </div>
        </section>
      ) : null}

      {error ? <ErrorBox message={error} /> : null}
      {loading && !data ? (
        <TableSkeleton rows={6} cols={3} />
      ) : (
        <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1 }}>
          <table>
            <thead>
              <tr>
                <th>Question</th>
                <th>Details</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {(data ?? []).map((q) => (
                <tr key={q.id}>
                  <td style={{ maxWidth: 520 }}>
                    <b>{truncate(q.question, 160)}</b>
                    <div className="meta">
                      ✓ {q.options?.[q.correct_index] ?? "—"}
                    </div>
                  </td>
                  <td>
                    <div className="meta">
                      #{q.id} · {q.category} · {q.difficulty}
                      {q.reference ? ` · ${q.reference}` : ""}
                    </div>
                    <span className={`chip ${q.is_published ? "green" : "grey"}`}>
                      {q.is_published ? "LIVE" : "HIDDEN"}
                    </span>
                  </td>
                  <td className="nowrap">
                    {canEdit ? (
                      <div className="actions">
                        <button
                          className="btn ghost sm"
                          onClick={() =>
                            setForm({
                              ...q,
                              options: [...q.options, ...Array(Math.max(0, 4 - q.options.length)).fill("")],
                              explanation: q.explanation ?? "",
                              reference: q.reference ?? "",
                            })
                          }
                        >
                          Edit
                        </button>
                        <button
                          className="btn red sm"
                          onClick={async () => {
                            const ok = await ask({
                              title: "Delete this question?",
                              sub: "It is removed for good. Unpublishing (Edit → untick Published) is usually better.",
                              confirmLabel: "Delete",
                              tone: "red",
                            });
                            if (ok === null) return;
                            try {
                              await rpc("admin_delete_quiz_question", { p_id: q.id });
                              toast.ok("Deleted.");
                              reload();
                            } catch (e) {
                              toast.err(e instanceof Error ? e.message : "Could not delete.");
                            }
                          }}
                        >
                          Delete
                        </button>
                      </div>
                    ) : null}
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
