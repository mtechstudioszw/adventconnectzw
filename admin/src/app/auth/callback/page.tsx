"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getBrowserSupabase } from "@/lib/supabase/browser";

/**
 * Magic-link landing. We accept any of the three Supabase formats:
 *   1. Implicit hash:  #access_token=...&refresh_token=...
 *   2. PKCE query:     ?code=...
 *   3. OTP query:      ?token_hash=...&type=magiclink
 *
 * After establishing a session we re-check the email against the
 * admin allowlist (via /api/admin-check) and bounce non-admins.
 * A client component is required for (1) because hash fragments
 * never reach the server.
 */
export default function CallbackPage() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const run = async () => {
      const supabase = getBrowserSupabase();

      // --- Format 1: hash fragment ---
      const hash = window.location.hash.startsWith("#")
        ? window.location.hash.slice(1)
        : "";
      const hashParams = new URLSearchParams(hash);
      const accessToken = hashParams.get("access_token");
      const refreshToken = hashParams.get("refresh_token");
      const hashError = hashParams.get("error_description");

      // --- Format 2/3: query string ---
      const search = new URLSearchParams(window.location.search);
      const code = search.get("code");
      const tokenHash = search.get("token_hash");
      const type = search.get("type");
      const queryError = search.get("error_description");

      if (hashError || queryError) {
        setError(hashError ?? queryError);
        return;
      }

      if (accessToken && refreshToken) {
        const { error: setSessionError } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });
        if (setSessionError) {
          setError(setSessionError.message);
          return;
        }
      } else if (code) {
        const { error: exchangeError } =
          await supabase.auth.exchangeCodeForSession(code);
        if (exchangeError) {
          setError(exchangeError.message);
          return;
        }
      } else if (tokenHash && type) {
        // verifyOtp's `type` enum varies by Supabase version. Cast
        // narrows the TS surface; the SDK validates at runtime.
        const { error: otpError } = await supabase.auth.verifyOtp({
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          type: type as any,
          token_hash: tokenHash,
        });
        if (otpError) {
          setError(otpError.message);
          return;
        }
      } else {
        setError("Missing authentication code in the link.");
        return;
      }

      // Check the email against the allowlist via a small route
      // handler. We can't reach process.env here in the browser.
      const check = await fetch("/api/admin-check", {
        method: "POST",
      });
      const checkBody = (await check.json()) as { allowed?: boolean };
      if (!checkBody.allowed) {
        await supabase.auth.signOut();
        setError("This email is not allowed in the admin panel.");
        return;
      }

      router.replace("/");
    };
    run();
    // Run once on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <main className="min-h-screen flex items-center justify-center p-6">
      <div className="w-full max-w-sm bg-white rounded-2xl shadow-md p-8 text-center">
        {error ? (
          <>
            <div className="text-3xl mb-3">⚠️</div>
            <h1 className="text-lg font-bold text-warn">Sign-in failed</h1>
            <p className="text-sm text-ink/70 mt-2">{error}</p>
            <a
              href="/login"
              className="mt-5 inline-block text-sm font-semibold text-primary hover:underline"
            >
              Back to login
            </a>
          </>
        ) : (
          <>
            <div className="text-3xl mb-3">🔐</div>
            <h1 className="text-lg font-bold text-navy">Signing you in…</h1>
            <p className="text-sm text-ink/60 mt-2">
              Verifying the link from your inbox.
            </p>
          </>
        )}
      </div>
    </main>
  );
}
