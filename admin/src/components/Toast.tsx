"use client";

import { createContext, useCallback, useContext, useMemo, useState } from "react";

/**
 * Toasts, replacing the `alert()` calls the old console used.
 *
 * `alert()` blocks the tab until it is dismissed, which is genuinely painful
 * when you are approving thirty things in a row — every approval costs an
 * extra click that tells you nothing you did not already know.
 */
type Tone = "ok" | "err" | "info";
type Toast = { id: number; tone: Tone; text: string };

type ToastApi = {
  ok: (text: string) => void;
  err: (text: string) => void;
  info: (text: string) => void;
};

const Ctx = createContext<ToastApi | null>(null);

let nextId = 1;

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const push = useCallback((tone: Tone, text: string) => {
    const id = nextId++;
    setToasts((t) => [...t, { id, tone, text }]);
    // Errors stay up longer — they usually say something you have to act on.
    window.setTimeout(
      () => setToasts((t) => t.filter((x) => x.id !== id)),
      tone === "err" ? 7000 : 3600,
    );
  }, []);

  const api = useMemo<ToastApi>(
    () => ({
      ok: (text) => push("ok", text),
      err: (text) => push("err", text),
      info: (text) => push("info", text),
    }),
    [push],
  );

  return (
    <Ctx.Provider value={api}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {toasts.map((t) => (
          <div className={`toast ${t.tone}`} key={t.id}>
            <span className="toast-dot" />
            <span>{t.text}</span>
          </div>
        ))}
      </div>
    </Ctx.Provider>
  );
}

export function useToast(): ToastApi {
  const v = useContext(Ctx);
  if (!v) throw new Error("useToast must be used inside <ToastProvider>");
  return v;
}
