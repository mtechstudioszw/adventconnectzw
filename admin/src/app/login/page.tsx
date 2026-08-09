"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase, configMissing } from "@/lib/supabase";
import { useSession } from "@/lib/session";
import { errorMessage } from "@/lib/rpc";
import { ErrorBox } from "@/components/ui";

export default function LoginPage() {
  const router = useRouter();
  const { session, role, loading, notStaff, signOut } = useSession();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Already signed in and cleared — go straight through.
  useEffect(() => {
    if (!loading && session && role) router.replace("/");
  }, [loading, session, role, router]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const { error: authError } = await supabase().auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (authError) throw authError;
      // The role check happens in SessionProvider and the redirect above.
      // Nothing is decided here — the database is what says who is staff.
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  if (configMissing) {
    return (
      <div className="login-page">
        <div className="login-card">
          <div className="login-mark">AC</div>
          <h1>Not configured</h1>
          <p className="sub">
            This deploy is missing <code>NEXT_PUBLIC_SUPABASE_URL</code> or{" "}
            <code>NEXT_PUBLIC_SUPABASE_ANON_KEY</code>. Set both in the Vercel
            project settings and redeploy.
          </p>
        </div>
      </div>
    );
  }

  // Signed in with a real Supabase account that is not staff. Saying so
  // plainly beats bouncing them back to a login form that just worked.
  if (session && notStaff && !loading) {
    return (
      <div className="login-page">
        <div className="login-card">
          <div className="login-mark">AC</div>
          <h1>Not a staff account</h1>
          <p className="sub">
            You are signed in as <b>{session.user.email}</b>, but this account has
            no role in the admin console. An owner can grant one under Staff &amp;
            roles.
          </p>
          <button className="btn ghost block" onClick={() => void signOut()}>
            Sign in as someone else
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-mark">AC</div>
        <h1>Admin console</h1>
        <p className="sub">Sign in with your Advent Connect account.</p>

        <form className="login-form" onSubmit={submit}>
          <div className="field">
            <label className="label" htmlFor="email">
              Email
            </label>
            <input
              id="email"
              className="input"
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="field">
            <label className="label" htmlFor="password">
              Password
            </label>
            <input
              id="password"
              className="input"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          {error ? <ErrorBox message={error} /> : null}

          <button className="btn primary block" type="submit" disabled={busy}>
            {busy ? <span className="spinner" /> : null}
            {busy ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <p className="login-note">
          Your role decides what you can do here, and the database enforces it on
          every action — not this page. Everything you change is recorded in the
          audit log.
        </p>
      </div>
    </div>
  );
}
