import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { middleware } from "@/middleware";
import { ACCESS_COOKIE, REFRESH_COOKIE } from "@/lib/session";

/**
 * The guard, asserted rather than assumed.
 *
 * What this protects against is specific and was real: `/links` rendered "Your
 * links", a New link button, and a failed request to somebody with no account,
 * because the only thing standing between an anonymous visitor and the
 * dashboard was a fetch that happened to 401. A redirect decided before the
 * page renders cannot half-work that way.
 *
 * The fixture is a refresh cookie holding an arbitrary string, and both halves
 * of that are deliberate. The guard tests presence, never contents — a test
 * that had to mint a real token would be asserting that this file verifies
 * them, which is precisely what it must not do. And it is the *refresh* cookie,
 * because that is the session; the example below about the access cookie is the
 * regression this file exists to hold.
 */

function request(path: string, { signedIn = false } = {}) {
  const url = `http://localhost:3000${path}`;
  const headers = signedIn ? { cookie: `${REFRESH_COOKIE}=an-opaque-refresh-token` } : undefined;

  return new NextRequest(url, { headers });
}

function redirectedTo(response: Response) {
  const location = response.headers.get("location");

  return location ? new URL(location) : null;
}

describe("the route guard", () => {
  it.each(["/links", "/links/new", "/links/abc/edit"])(
    "sends an anonymous visitor from %s to sign-in",
    (path) => {
      const response = middleware(request(path));

      expect(response.status).toBe(307);
      expect(redirectedTo(response)?.pathname).toBe("/sign-in");
    },
  );

  it("remembers where they were going, so signing in finishes the journey", () => {
    const response = middleware(request("/links/new?from=poster"));

    expect(redirectedTo(response)?.searchParams.get("next")).toBe("/links/new?from=poster");
  });

  it("lets a signed-in visitor through", () => {
    const response = middleware(request("/links", { signedIn: true }));

    expect(response.headers.get("location")).toBeNull();
  });

  it.each(["/sign-in", "/sign-up"])(
    "sends a signed-in visitor from %s to the dashboard",
    (path) => {
      const response = middleware(request(path, { signedIn: true }));

      expect(redirectedTo(response)?.pathname).toBe("/links");
    },
  );

  it("leaves the auth screens alone for anyone without a session", () => {
    const response = middleware(request("/sign-in"));

    expect(response.headers.get("location")).toBeNull();
  });

  /*
   * The regression, reported by hand: deleting the access cookie signed the
   * person out completely instead of fetching a new one.
   *
   * An absent access token is the ordinary recoverable state — it expires every
   * fifteen minutes — and the remedy is one refresh request that the dashboard
   * makes on its own. A guard that redirected here never let the page render,
   * so that request was never made.
   */
  it("lets a session through with no access cookie at all", () => {
    const request = new NextRequest("http://localhost:3000/links", {
      headers: { cookie: `${REFRESH_COOKIE}=an-opaque-refresh-token` },
    });

    expect(middleware(request).headers.get("location")).toBeNull();
  });

  it("does not accept an access cookie as evidence of a session", () => {
    const request = new NextRequest("http://localhost:3000/links", {
      headers: { cookie: `${ACCESS_COOKIE}=header.payload.signature` },
    });

    expect(redirectedTo(middleware(request))?.pathname).toBe("/sign-in");
  });

  // Presence only, and of an opaque string this file must never try to read.
  it("does not inspect the token, only whether one is there", () => {
    const request = new NextRequest("http://localhost:3000/links", {
      headers: { cookie: `${REFRESH_COOKIE}=not-even-base64` },
    });

    expect(middleware(request).headers.get("location")).toBeNull();
  });

  // Sign-out has to work while signed in and must not bounce once it is done,
  // so it belongs to neither list.
  it("never redirects sign-out, in either direction", () => {
    expect(middleware(request("/sign-out")).headers.get("location")).toBeNull();
    expect(middleware(request("/sign-out", { signedIn: true })).headers.get("location")).toBeNull();
  });
});
