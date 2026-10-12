import { NextResponse, type NextRequest } from "next/server";

import { REFRESH_COOKIE } from "@/lib/session";

/**
 * Who is allowed to see which screen, decided before a page renders.
 *
 * Doing it here rather than in the pages is what makes it a guarantee. A
 * dashboard that renders first and redirects from an effect has already drawn
 * "Your links" and a New link button to somebody with no account — which is
 * exactly what it did before this file existed — and a client-side guard cannot
 * be relied on at all with JavaScript disabled or still loading.
 *
 * The test is whether the *refresh* cookie is present, and which cookie that is
 * matters more than anything else in this file.
 *
 * It tested `snip_access` for one revision, and that was wrong in a way a
 * manual test found at once: deleting the access cookie signed the person out.
 * The access token is a transient — it expires every fifteen minutes, and its
 * absence is the ordinary, recoverable state that a refresh exists to fix. A
 * guard that read absence as "signed out" redirected to `/sign-in` before the
 * page could render, so the client-side refresh that would have recovered the
 * session in one request never ran. The session is the refresh-token family, so
 * the session's cookie is the one to ask about.
 *
 * Presence, and nothing more. This code does not decode anything, check an
 * expiry, or verify a signature, and it must not start. Whether a credential is
 * valid, and what it permits, is Rails' answer to give on each request.
 *
 * Which means this test can still be wrong, in the harmless direction. A
 * revoked session, or a hand-written cookie, reaches a dashboard whose every
 * request comes back 401 — and `src/lib/api.ts` sends them to sign in the
 * moment the refresh is refused. That is the correct amount of trust to place
 * in any cookie: enough to route on, never enough to authorise on.
 */

/** Everything under the dashboard. Nothing here makes sense signed out. */
const PROTECTED = ["/links"];

/** The two screens that make no sense signed *in*. */
const GUEST_ONLY = ["/sign-in", "/sign-up"];

function matches(pathname: string, prefixes: string[]) {
  return prefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));
}

export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const signedIn = request.cookies.has(REFRESH_COOKIE);

  if (!signedIn && matches(pathname, PROTECTED)) {
    const signIn = new URL("/sign-in", request.url);

    // Where they were going, so signing in finishes the journey instead of
    // dropping them on a list they did not ask for.
    signIn.searchParams.set("next", `${pathname}${search}`);

    return NextResponse.redirect(signIn);
  }

  if (signedIn && matches(pathname, GUEST_ONLY)) {
    return NextResponse.redirect(new URL("/links", request.url));
  }

  return NextResponse.next();
}

export const config = {
  /*
   * `/sign-out` is deliberately absent from both lists: it has to work while
   * signed in and must not bounce once it has finished, so it is left to run.
   */
  matcher: ["/links/:path*", "/sign-in", "/sign-up"],
};
