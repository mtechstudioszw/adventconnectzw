import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refreshes the Supabase auth cookie on every navigation so server
 * components see a fresh session. We DO NOT perform the email-allowlist
 * gate here — pages call `requireAdmin()` directly so the check
 * happens at the most-specific scope and unauthenticated visitors
 * still get the login page.
 */
export async function middleware(request: NextRequest) {
  const response = NextResponse.next({
    request: { headers: request.headers },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: Record<string, unknown>) {
          request.cookies.set({ name, value, ...options });
          response.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: Record<string, unknown>) {
          request.cookies.set({ name, value: "", ...options });
          response.cookies.set({ name, value: "", ...options });
        },
      },
    },
  );

  // Touching getUser refreshes the cookie if needed.
  await supabase.auth.getUser();

  return response;
}

export const config = {
  matcher: [
    // Run on every request except Next internals and static assets.
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
