"use client";

import { useEffect, useRef, useState } from "react";
import { IconAlert, IconInbox, IconInfo } from "./icons";
import { fmtNum } from "@/lib/format";

/* ---- page header ------------------------------------------------------- */

export function PageHead({
  title,
  sub,
  actions,
}: {
  title: string;
  sub?: string;
  actions?: React.ReactNode;
}) {
  return (
    <div className="row" style={{ marginBottom: 18, alignItems: "flex-start" }}>
      <div style={{ minWidth: 0 }}>
        <h2 style={{ fontSize: 19, fontWeight: 700, letterSpacing: "-0.4px" }}>
          {title}
        </h2>
        {sub ? (
          <p className="meta" style={{ marginTop: 3, maxWidth: 640 }}>
            {sub}
          </p>
        ) : null}
      </div>
      {actions ? (
        <div className="actions" style={{ marginLeft: "auto" }}>
          {actions}
        </div>
      ) : null}
    </div>
  );
}

/* ---- states ------------------------------------------------------------ */

export function Empty({ title, sub }: { title: string; sub?: string }) {
  return (
    <div className="empty">
      <IconInbox className="empty-icon" size={40} />
      <div className="empty-title">{title}</div>
      {sub ? <div className="meta">{sub}</div> : null}
    </div>
  );
}

export function ErrorBox({ message }: { message: string }) {
  return (
    <div className="error-box" role="alert">
      <IconAlert size={17} style={{ flexShrink: 0, marginTop: 1 }} />
      <span>{message}</span>
    </div>
  );
}

export function Note({ children }: { children: React.ReactNode }) {
  return (
    <div className="note">
      <IconInfo className="note-icon" size={16} />
      <div>{children}</div>
    </div>
  );
}

/** Table-shaped skeleton, so the page does not jump when rows arrive. */
export function TableSkeleton({ rows = 4, cols = 3 }: { rows?: number; cols?: number }) {
  return (
    <div className="table-wrap" aria-busy="true" aria-label="Loading">
      <table>
        <tbody>
          {Array.from({ length: rows }).map((_, r) => (
            <tr key={r}>
              {Array.from({ length: cols }).map((__, c) => (
                <td key={c}>
                  <div
                    className="skeleton"
                    style={{
                      height: 13,
                      width: c === 0 ? "62%" : `${34 + ((r + c) % 3) * 12}%`,
                    }}
                  />
                  {c === 0 ? (
                    <div
                      className="skeleton"
                      style={{ height: 10, width: "42%", marginTop: 7 }}
                    />
                  ) : null}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function TilesSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="tiles" aria-busy="true">
      {Array.from({ length: count }).map((_, i) => (
        <div className="tile" key={i}>
          <div className="skeleton" style={{ height: 11, width: "58%" }} />
          <div className="skeleton" style={{ height: 26, width: "42%", marginTop: 10 }} />
        </div>
      ))}
    </div>
  );
}

/* ---- tiles ------------------------------------------------------------- */

export function Tile({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: number | string;
  sub?: string;
  /** `alert` only when the number is something to act on today. */
  tone?: "alert" | "danger";
}) {
  const numeric = typeof value === "number";
  const hot = tone && numeric && Number(value) > 0;
  return (
    <div className={`tile${hot ? ` ${tone}` : ""}`}>
      <div className="tile-label">{label}</div>
      <div className="tile-value">{numeric ? fmtNum(value) : value}</div>
      {sub ? <div className="tile-sub">{sub}</div> : null}
    </div>
  );
}

/* ---- chips ------------------------------------------------------------- */

const STATUS_TONE: Record<string, string> = {
  open: "gold",
  new: "gold",
  pending: "gold",
  final_review_pending: "red",
  actioned: "green",
  resolved: "green",
  approved: "green",
  active: "green",
  dismissed: "grey",
  disabled: "grey",
  rejected: "red",
  revoked: "red",
  banned: "red",
};

export function StatusChip({ status }: { status: string | null | undefined }) {
  const s = String(status ?? "").toLowerCase();
  return (
    <span className={`chip ${STATUS_TONE[s] ?? "grey"}`}>
      {s.replace(/_/g, " ").toUpperCase() || "—"}
    </span>
  );
}

/* ---- filter control ---------------------------------------------------- */

export function Segmented<T extends string>({
  options,
  value,
  onChange,
  labels,
}: {
  options: readonly T[];
  value: T;
  onChange: (next: T) => void;
  labels?: Partial<Record<T, string>>;
}) {
  return (
    <div className="segmented" role="tablist">
      {options.map((o) => (
        <button
          key={o}
          type="button"
          role="tab"
          aria-selected={o === value}
          className={o === value ? "on" : ""}
          onClick={() => onChange(o)}
        >
          {labels?.[o] ?? o.charAt(0).toUpperCase() + o.slice(1).replace(/_/g, " ")}
        </button>
      ))}
    </div>
  );
}

/* ---- search box -------------------------------------------------------- */

export function SearchBox({
  placeholder,
  onSearch,
  defaultValue = "",
}: {
  placeholder: string;
  onSearch: (query: string) => void;
  defaultValue?: string;
}) {
  const [q, setQ] = useState(defaultValue);
  return (
    <form
      className="row"
      style={{ gap: 8 }}
      onSubmit={(e) => {
        e.preventDefault();
        onSearch(q.trim());
      }}
    >
      <input
        className="input"
        style={{ maxWidth: 300 }}
        placeholder={placeholder}
        value={q}
        onChange={(e) => setQ(e.target.value)}
      />
      <button className="btn primary" type="submit">
        Search
      </button>
    </form>
  );
}

/* ---- a button that shows its own progress ------------------------------ */

export function BusyButton({
  onClick,
  children,
  className = "btn",
  disabled,
  title,
}: {
  onClick: () => Promise<unknown> | unknown;
  children: React.ReactNode;
  className?: string;
  disabled?: boolean;
  title?: string;
}) {
  const [busy, setBusy] = useState(false);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  return (
    <button
      type="button"
      className={className}
      disabled={busy || disabled}
      title={title}
      onClick={async () => {
        if (busy) return;
        setBusy(true);
        try {
          await onClick();
        } finally {
          // The row this button lives in is usually gone by now — the list
          // reloads on success. Guard, or React warns on every action.
          if (alive.current) setBusy(false);
        }
      }}
    >
      {busy ? <span className="spinner" /> : null}
      {children}
    </button>
  );
}

/* ---- text field with a live counter ------------------------------------ */

export function CountedField({
  label,
  value,
  onChange,
  max,
  placeholder,
  textarea,
  rows,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  max: number;
  placeholder?: string;
  textarea?: boolean;
  rows?: number;
}) {
  const left = max - value.length;
  return (
    <div className="field">
      <label className="label">{label}</label>
      {textarea ? (
        <textarea
          className="textarea"
          maxLength={max}
          rows={rows}
          placeholder={placeholder}
          value={value}
          onChange={(e) => onChange(e.target.value)}
        />
      ) : (
        <input
          className="input"
          maxLength={max}
          placeholder={placeholder}
          value={value}
          onChange={(e) => onChange(e.target.value)}
        />
      )}
      {/* Only once it is relevant — a counter sitting at 480 of 500 from the
          first keystroke is noise. */}
      {left <= max * 0.25 ? (
        <div className={`char-count${left <= 20 ? " warn" : ""}`}>{left} left</div>
      ) : null}
    </div>
  );
}
