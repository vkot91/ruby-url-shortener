import { cookies } from "next/headers";
import { NextResponse } from "next/server";

import {
  ACCESS_COOKIE,
  ACCESS_COOKIE_PATH,
  REFRESH_COOKIE,
  REFRESH_COOKIE_PATH,
} from "@/lib/session";

/**
 * The pieces the four handlers under `src/app/api/auth/` share (research.md D10).
 *
 * The whole point of the BFF is that exactly one process ever holds the refresh
 * token: Rails issues it, Next.js keeps it in an httpOnly cookie on its own
 * origin, and the browser never sees it. Everything in this file exists to make
 * that boundary hard to cross by accident — `openSession` is the only place a
 * Rails token pair is turned into a browser response, and it drops the refresh
 * token on the way through rather than trusting each handler to remember to.
 */

/**
 * Fourteen days, matching the refresh-token lifetime in data-model.md. The
 * cookie outliving the token would mean a client that believes it has a session
 * and gets a 401 on every refresh; the token outliving the cookie would mean
 * signing people out early for no reason. Both cookies carry it, so they cannot
 * disagree about whether a session exists.
 */
const SESSION_MAX_AGE = 60 * 60 * 24 * 14;

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

/**
 * The domain the session cookies are scoped to, so that the API on another
 * origin receives them.
 *
 * Unset locally, and that is not an omission: a host-only cookie for
 * `localhost` already reaches `localhost:3001`, because cookies are not
 * isolated by port. In production the dashboard and the API have to be siblings
 * under one registrable domain — `app.snip.to` and `api.snip.to` with
 * `SESSION_COOKIE_DOMAIN=.snip.to` — and this is the line that says so. Two
 * unrelated domains would make the arrangement cross-site, which is the
 * situation research.md D10 rejected and this does not resurrect.
 *
 * The short domain is deliberately not in that family. `snp.to` is a different
 * registrable domain, so no session cookie is ever sent with a redirect.
 */
const COOKIE_DOMAIN = process.env.SESSION_COOKIE_DOMAIN || undefined;

export type TokenPair = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
};

export async function apiRequest(path: string, body: unknown, method = "POST") {
  return fetch(`${API_URL}/api/v1${path}`, {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    // A BFF hop is server-to-server and must never be served from a cache: the
    // response carries a credential that is valid exactly once.
    cache: "no-store",
  });
}

export async function readRefreshToken(): Promise<string | null> {
  const store = await cookies();

  return store.get(REFRESH_COOKIE)?.value ?? null;
}

/**
 * The one door between Rails' token pair and the browser.
 *
 * Neither token reaches the response body. Both become httpOnly cookies, so
 * there is nothing for an XSS on the dashboard to read and nothing for the
 * client to hold, lose on reload, and have to mint again — which is what the
 * previous in-memory arrangement did on every page load, and what made two tabs
 * opening at once look like token theft.
 *
 * The body carries `expires_in` alone, and only as information: the token's own
 * `exp` claim is what Rails enforces.
 *
 * Nothing about *who* signed in is written anywhere here, and that is the point:
 * a token pair carries no identity, so this function has none to record without
 * inventing it. `GET /api/v1/me` is where identity comes from.
 */
export function openSession(pair: TokenPair, { status = 200 }: { status?: number } = {}) {
  const { access_token, expires_in, refresh_token } = pair;

  const response = NextResponse.json({ expires_in }, { status });

  setCookie(response, REFRESH_COOKIE, refresh_token, {
    httpOnly: true,
    path: REFRESH_COOKIE_PATH,
  });

  // Given the session's lifetime rather than the token's. The cookie outliving
  // the token is deliberate: an expired token still arrives, so Rails answers
  // `token_expired` and the client knows to refresh. A cookie that expired
  // first would simply vanish, and the client would be told `unauthenticated` —
  // the code that means "sign in again", for a session that was fine.
  setCookie(response, ACCESS_COOKIE, access_token, {
    httpOnly: true,
    path: ACCESS_COOKIE_PATH,
  });

  return response;
}

export function closeSession(response: NextResponse) {
  expireCookie(response, REFRESH_COOKIE, { httpOnly: true, path: REFRESH_COOKIE_PATH });
  expireCookie(response, ACCESS_COOKIE, { httpOnly: true, path: ACCESS_COOKIE_PATH });

  return response;
}

type CookieOptions = { httpOnly: boolean; path?: string };

function cookieDefaults({ httpOnly, path = "/" }: CookieOptions) {
  return {
    httpOnly,
    domain: COOKIE_DOMAIN,
    // Lax, and it is doing real work now that a cookie authenticates: a
    // cross-site POST or fetch carries no cookie at all, which is this
    // application's CSRF answer. It costs nothing, because the dashboard and
    // the API are same-site by requirement — see COOKIE_DOMAIN.
    sameSite: "lax" as const,
    // Off in development, where the dev server is plain HTTP and a Secure
    // cookie would simply never be stored — which looks like a broken sign-in
    // rather than like a misconfiguration.
    secure: process.env.NODE_ENV === "production",
    path,
  };
}

function setCookie(response: NextResponse, name: string, value: string, options: CookieOptions) {
  response.cookies.set({ name, value, ...cookieDefaults(options), maxAge: SESSION_MAX_AGE });
}

function expireCookie(response: NextResponse, name: string, options: CookieOptions) {
  response.cookies.set({ name, value: "", ...cookieDefaults(options), maxAge: 0 });
}

/**
 * Relays a refusal from Rails to the browser without inventing one of its own.
 *
 * `error.code` is deliberately not translated on the way through. FR-036
 * requires sign-in to give one indistinguishable answer whatever went wrong,
 * and that answer is already decided in Rails — re-deciding it here would be a
 * second place for the two to drift apart, in the one place where drift leaks
 * whether an email address is registered.
 *
 * What it does do is keep the response honest about its own shape. Not every
 * refusal that reaches here comes from Rails: a proxy 502, a container that is
 * still booting, or Rails' own HTML error page in production all arrive as
 * something other than JSON, and the previous version of this function stamped
 * `Content-Type: application/json` on them regardless — so the client parsed an
 * HTML page, threw, and reported nothing useful. Anything that did not arrive
 * as JSON is given the envelope the contract promises, built from the status.
 *
 * The application's own 429s are unaffected: `RateLimiting#render_rate_limited`
 * sends the envelope already, and it passes through untouched — which is what
 * FR-036 needs, since the throttled sign-in body has to stay byte-identical to
 * the refused one.
 */
export async function forwardFailure(response: Response) {
  const contentType = response.headers.get("Content-Type") ?? "";
  const body = await response.text();

  if (contentType.includes("application/json") && body.length > 0) {
    return new NextResponse(body, {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  const code = response.status === 429 ? "rate_limited" : "request_failed";
  const message =
    response.status === 429 ? "Too many attempts. Try again shortly." : "Something went wrong.";

  return NextResponse.json({ error: { code, message } }, { status: response.status });
}
