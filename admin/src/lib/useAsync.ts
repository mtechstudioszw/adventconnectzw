"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { errorMessage } from "./rpc";

export type AsyncState<T> = {
  data: T | null;
  error: string | null;
  loading: boolean;
  /** Re-runs the loader. Safe to pass straight to a Refresh button. */
  reload: () => void;
};

/**
 * Load-on-mount with reload, cancellation and a settled error string.
 *
 * The console is a stack of "fetch a list, act on a row, fetch it again"
 * screens, and every one of them otherwise grows the same four pieces of
 * state plus the same stale-response bug: act on a row, the list reloads,
 * the *first* request lands last and puts the acted-on row back on screen.
 * A generation counter is the whole fix, so it lives here once.
 *
 * `deps` follows the usual rules — anything the loader closes over belongs
 * in it.
 */
export function useAsync<T>(
  loader: () => Promise<T>,
  deps: React.DependencyList = [],
): AsyncState<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);

  const generation = useRef(0);
  const alive = useRef(true);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const loaderRef = useRef(loader);
  loaderRef.current = loader;

  useEffect(() => {
    const gen = ++generation.current;
    setLoading(true);
    setError(null);

    loaderRef
      .current()
      .then((result) => {
        if (!alive.current || gen !== generation.current) return;
        setData(result);
      })
      .catch((e) => {
        if (!alive.current || gen !== generation.current) return;
        setError(errorMessage(e));
      })
      .finally(() => {
        if (!alive.current || gen !== generation.current) return;
        setLoading(false);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nonce, ...deps]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);

  return { data, error, loading, reload };
}
