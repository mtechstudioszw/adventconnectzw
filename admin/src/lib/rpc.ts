"use client";

import { supabase } from "./supabase";

/**
 * Call an admin RPC and get back typed rows, or throw an error a
 * non-technical person can act on.
 *
 * Postgres speaks in SQLSTATEs. "42501" and "new row violates row-level
 * security policy" are correct and useless to someone whose job is clearing
 * a moderation queue, so the codes we can actually predict are translated
 * here, once, instead of in twenty catch blocks.
 */
export async function rpc<T = unknown>(
  fn: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new RpcError(error, fn);
  return data as T;
}

/** Same, for RPCs that return SETOF — guarantees an array back. */
export async function rpcList<T = unknown>(
  fn: string,
  args: Record<string, unknown> = {},
): Promise<T[]> {
  const data = await rpc<T[] | null>(fn, args);
  return Array.isArray(data) ? data : [];
}

type PgError = { message: string; code?: string; hint?: string | null };

export class RpcError extends Error {
  readonly code?: string;
  readonly fn: string;

  constructor(error: PgError, fn: string) {
    super(friendly(error, fn));
    this.name = "RpcError";
    this.code = error.code;
    this.fn = fn;
  }
}

function friendly(error: PgError, fn: string): string {
  const raw = error.message ?? "";

  // The server refusing on role. This is the single most likely error a
  // moderator will ever see, and "permission denied for function" would
  // send them to the founder for no reason.
  if (error.code === "42501" || /not authorized|assert_staff|permission denied/i.test(raw)) {
    if (raw.includes("MAINTENANCE_MODE")) {
      return "Maintenance mode is on, so this write was refused. Turn it off first.";
    }
    return "Your role does not allow that. Ask an owner to do it, or to raise your role.";
  }

  // The guard that stops the console locking everybody out.
  if (error.code === "23514" && /owner/i.test(raw)) {
    return "That would remove the last owner. Promote someone else to owner first — otherwise nobody can get back into this console.";
  }

  // A function the deploy expects but the database does not have. Worth
  // naming explicitly: it means this build is ahead of the database.
  if (error.code === "42883" || /function .* does not exist/i.test(raw)) {
    return `This console expected "${fn}" to exist in the database, and it does not. A migration has probably not been applied.`;
  }

  if (/JWT|token is expired/i.test(raw)) {
    return "Your session expired. Sign in again.";
  }

  if (/fetch|network|Failed to fetch/i.test(raw)) {
    return "Could not reach the server. Check your connection and try again.";
  }

  return raw || "Something went wrong.";
}

/** Narrow an unknown catch value to a message safe to show. */
export function errorMessage(e: unknown): string {
  if (e instanceof Error) return e.message;
  return typeof e === "string" ? e : "Something went wrong.";
}
