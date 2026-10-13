/**
 * What both sides of the BFF boundary agree a session looks like.
 *
 * Two cookies, both httpOnly, both written by the BFF and readable by nothing
 * in the browser. There is deliberately no third cookie describing who is
 * signed in: that question is `GET /api/v1/me`'s to answer, because a cookie
 * can only report what was true when it was written, and an address corrected
 * or a role granted after sign-in would not appear in it until the session was
 * closed and opened again.
 *
 * Deliberately free of `next/headers` and `next/server` so it can be imported
 * from the browser as well as from a route handler — `src/lib/bff.ts` cannot,
 * and pulling it into client code would drag server-only modules into the
 * bundle.
 */

/** The durable credential. httpOnly, so nothing here can read it — only send it. */
export const REFRESH_COOKIE = "snip_refresh";

/**
 * `/`, because this cookie is the session and `src/middleware.ts` has to see it.
 *
 * It was `/api/auth` on the reasoning that a fourteen-day credential should
 * reach only the handlers that can spend it. That was tidy and it was wrong,
 * for a reason a manual test found immediately: with the guard testing
 * `snip_access` instead, deleting the access cookie signed the person out. The
 * guard redirected to `/sign-in` before the page rendered, so the client-side
 * refresh — which would have recovered the session in one request — never ran.
 *
 * Which cookie means "signed in" is the whole of that mistake. The access token
 * is a transient: it expires every fifteen minutes, and its absence is an
 * ordinary, recoverable state. The refresh token is the session, so it is the
 * one the guard asks about, and it has to be sent to the pages being guarded.
 *
 * It stays httpOnly, `SameSite=Lax`, and on the app origin's own domain.
 */
export const REFRESH_COOKIE_PATH = "/";

/**
 * The access token, as a cookie rather than as a value JavaScript holds.
 *
 * Set by the BFF on a domain both origins share — cookies are not isolated by
 * port (RFC 6265 §8.5), so one set for `localhost` reaches the API on another
 * port, and in production `SESSION_COOKIE_DOMAIN` makes it reach a sibling
 * subdomain. Rails reads it in the `Authentication` concern, where the name is
 * repeated and this file is named as the place it is written.
 *
 * httpOnly, so an XSS cannot read it — which is a real improvement over both
 * localStorage and the module variable this replaces, since a variable that
 * died with the page meant every reload spent a refresh token to mint another.
 */
export const ACCESS_COOKIE = "snip_access";

/**
 * `/`, so that the dashboard layout can read it on a page request and ask
 * `GET /api/v1/me` who is signed in before rendering the header.
 *
 * Note what this cookie is *not* used for: deciding whether somebody is signed
 * in. Its absence is an ordinary state — the browser cleared it, or a person
 * deleted it by hand — and the correct response is to spend a refresh token,
 * not to sign anybody out. `src/middleware.ts` therefore asks about
 * REFRESH_COOKIE and never about this one.
 *
 * What it does *not* do is put a credential on the redirect path. In production
 * the short domain is a different registrable domain from the one
 * `SESSION_COOKIE_DOMAIN` names, so no session cookie is sent there at all. In
 * development they share `localhost` and it is: the redirect runs in middleware
 * ahead of the router, reads no credential of any kind, and — with
 * `ActionDispatch::Cookies` absent from the stack — cannot set one in reply
 * (FR-015, Principle V, which governs what is *set* on that path).
 */
export const ACCESS_COOKIE_PATH = "/";
