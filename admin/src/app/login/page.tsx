"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { getBrowserSupabase } from "@/lib/supabase/browser";

export default function LoginPage() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  // If the callback bounced the user back here, show the reason.
  useEffect(() => {
    const fromCallback = params.get("error");
    if (fromCallback) setErrorMessage(fromCallback);
  }, [params]);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setSubmitting(true);
    setErrorMessage("");

    const supabase = getBrowserSupabase();
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      setSubmitting(false);
      setErrorMessage(error.message);
      return;
    }

    // Re-check the email against the admin allowlist server-side
    // before letting them into the dashboard. Banishes anyone whose
    // address isn't in ADMIN_EMAILS even if Supabase issued a session.
    const check = await fetch("/api/admin-check", { method: "POST" });
    const checkBody = (await check.json()) as { allowed?: boolean };
    if (!checkBody.allowed) {
      await supabase.auth.signOut();
      setSubmitting(false);
      setErrorMessage("This email is not allowed in the admin panel.");
      return;
    }

    router.replace("/");
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
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:border-primary focus:outline-none text-sm"
              placeholder="you@example.com"
            />
          </div>
          <div className="space-y-1">
            <label
              htmlFor="password"
              className="text-xs font-semibold text-ink/70"
            >
              Password
            </label>
            <input
              id="password"
              type="password"
              required
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="w-full px-3 py-2.5 rounded-xl border border-ink/10 bg-canvas focus:bg-white focus:border-primary focus:outline-none text-sm"
              placeholder="••••••••"
            />
          </div>
          <button
            type="submit"
            disabled={submitting}
            className="w-full bg-primary text-white rounded-xl py-2.5 text-sm font-semibold hover:opacity-95 disabled:opacity-60"
          >
            {submitting ? "Signing in…" : "Sign in"}
          </button>
          {errorMessage && (
            <p className="text-xs text-warn">{errorMessage}</p>
          )}
          <p className="text-[11px] text-ink/50 leading-relaxed">
            Set a password in Supabase Dashboard → Authentication → Users
            → click your user → &ldquo;Reset/send password&rdquo; or use
            the user-edit dialog.
          </p>
        </form>
      </div>
    </main>
  );
}
