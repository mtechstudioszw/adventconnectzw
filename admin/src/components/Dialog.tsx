"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

/**
 * A promise-based confirm/prompt, so an action reads as one straight line:
 *
 *   const reason = await ask({ title: "Reject seller", ... });
 *   if (reason === null) return;
 *
 * Resolves to `null` on cancel, the typed string when `input` is set, and
 * `""` for a plain confirm. That distinction matters: an empty reason is a
 * legitimate answer ("reject, no comment") and must not read as a cancel.
 */
export type AskOptions = {
  title: string;
  sub?: string;
  input?: { placeholder?: string; multiline?: boolean; required?: boolean };
  confirmLabel?: string;
  tone?: "primary" | "red" | "green";
  /**
   * Makes the operator type an exact word before Confirm enables. Reserved
   * for the things that touch everybody at once — turning the app off, or
   * broadcasting to every member.
   */
  typeToConfirm?: string;
};

type AskFn = (options: AskOptions) => Promise<string | null>;

const Ctx = createContext<AskFn | null>(null);

type Pending = AskOptions & { resolve: (value: string | null) => void };

export function DialogProvider({ children }: { children: React.ReactNode }) {
  const [pending, setPending] = useState<Pending | null>(null);
  const [text, setText] = useState("");
  const [confirmText, setConfirmText] = useState("");
  const inputRef = useRef<HTMLTextAreaElement | HTMLInputElement | null>(null);

  const ask = useCallback<AskFn>(
    (options) =>
      new Promise((resolve) => {
        setText("");
        setConfirmText("");
        setPending({ ...options, resolve });
      }),
    [],
  );

  const close = useCallback(
    (value: string | null) => {
      setPending((p) => {
        p?.resolve(value);
        return null;
      });
    },
    [],
  );

  useEffect(() => {
    if (!pending) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close(null);
    };
    window.addEventListener("keydown", onKey);
    // Focus lands in the field so a reason can be typed without reaching for
    // the mouse — this dialog opens dozens of times in a queue session.
    const id = window.setTimeout(() => inputRef.current?.focus(), 40);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.clearTimeout(id);
    };
  }, [pending, close]);

  const value = useMemo(() => ask, [ask]);

  const gateOk = !pending?.typeToConfirm
    ? true
    : confirmText.trim().toUpperCase() === pending.typeToConfirm.toUpperCase();
  const requiredOk = !pending?.input?.required || text.trim().length > 0;
  const canConfirm = gateOk && requiredOk;

  return (
    <Ctx.Provider value={value}>
      {children}
      {pending ? (
        <div
          className="dialog-scrim"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) close(null);
          }}
        >
          <div className="dialog" role="dialog" aria-modal="true" aria-label={pending.title}>
            <h3>{pending.title}</h3>
            {pending.sub ? <p className="dialog-sub">{pending.sub}</p> : null}

            {pending.input ? (
              <div style={{ marginTop: 16 }}>
                {pending.input.multiline ? (
                  <textarea
                    ref={(el) => {
                      inputRef.current = el;
                    }}
                    className="textarea"
                    placeholder={pending.input.placeholder}
                    value={text}
                    onChange={(e) => setText(e.target.value)}
                  />
                ) : (
                  <input
                    ref={(el) => {
                      inputRef.current = el;
                    }}
                    className="input"
                    placeholder={pending.input.placeholder}
                    value={text}
                    onChange={(e) => setText(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" && canConfirm) close(text.trim());
                    }}
                  />
                )}
              </div>
            ) : null}

            {pending.typeToConfirm ? (
              <div style={{ marginTop: 16 }} className="field">
                <label className="label">
                  Type <b>{pending.typeToConfirm}</b> to confirm
                </label>
                <input
                  ref={
                    pending.input
                      ? undefined
                      : (el) => {
                          inputRef.current = el;
                        }
                  }
                  className="input"
                  value={confirmText}
                  onChange={(e) => setConfirmText(e.target.value)}
                  autoComplete="off"
                  spellCheck={false}
                />
              </div>
            ) : null}

            <div className="dialog-actions">
              <button className="btn ghost" type="button" onClick={() => close(null)}>
                Cancel
              </button>
              <button
                className={`btn ${pending.tone ?? "primary"}`}
                type="button"
                disabled={!canConfirm}
                onClick={() => close(pending.input ? text.trim() : "")}
              >
                {pending.confirmLabel ?? "Confirm"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </Ctx.Provider>
  );
}

export function useAsk(): AskFn {
  const v = useContext(Ctx);
  if (!v) throw new Error("useAsk must be used inside <DialogProvider>");
  return v;
}
