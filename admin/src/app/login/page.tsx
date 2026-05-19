"use client";

import { useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase/browser";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<
    "idle" | "sending" | "sent" | "error"
  >("idle");
  const [errorMessage, setErrorMessage] = useState("");

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setStatus("sending");
    setErrorMessage("");

    const supabase = getBrowserSupabase();
    const redirectTo =
      typeof window !== "undefined"
        ? `${window.location.origin}/auth/callback`
        : undefined;

    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        // Do NOT create new users via the admin panel — anyone signing
        // in must already exist in auth.users. The allowlist check
        // happens server-side either way.
        shouldCreateUser: false,
        emailRedirectTo: redirectTo,
      },
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
      return;
    }
    setStatus("sent");
  };

  return (
    <main className="min-h-screen flex items-center justify-center p-6">
      <div className="w-full max-w-sm bg-white rounded-2xl shadow-md p-8">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-xl bg-primary text-white grid place-items-center font-bold">
            AC
          </div>
          <div>
            <h1 className="text-lg font-bold text-navy leading-tight">
              Admin panel
            </h1>
            <p className="text-xs text-ink/60">Advent Connect ZW</p>
          </div>
        </div>

        {status === "sent" ? (
          <div className="space-y-3">
            <p className="text-sm text-ink">
              Magic link sent to <span className="font-semibold">{email}</span>.
            </p>
            <p className="text-xs text-ink/60">
              Open the email on this device and tap the link to finish signing
              in. Only allowlisted admins can access the panel — if you
              don&apos;t see the email and your address isn&apos;t on the
              list, nothing will arrive.
            </p>
          </div>
        ) : (
          <form className="space-y-4" onSubmit={handleSubmit}>
            <div className="space-y-1">
              <label
                htmlFor="email"
                className="text-xs font-semibold text-ink/70"
              >
                Email
              </label>
              <input
                id="email"
                type="email"
                required
                autoFocus
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:border-primary focus:outline-none text-sm"
                placeholder="you@example.com"
              />
            </div>
            <button
              type="submit"
              disabled={status === "sending"}
              className="w-full bg-primary text-white rounded-xl py-2.5 text-sm font-semibold hover:opacity-95 disabled:opacity-60"
            >
              {status === "sending" ? "Sending…" : "Send magic link"}
            </button>
            {errorMessage && (
              <p className="text-xs text-warn">{errorMessage}</p>
            )}
            <p className="text-[11px] text-ink/50 leading-relaxed">
              You&apos;ll receive a one-time link to this address. Sessions
              expire on inactivity.
            </p>
          </form>
        )}
      </div>
    </main>
  );
}
