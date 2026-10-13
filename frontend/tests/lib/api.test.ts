import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { getAccount, listLinks } from "@/lib/api";

/**
 * research.md D10's client half, as amended twice.
 *
 * The client holds no credential — both tokens are httpOnly cookies the BFF
 * wrote — and, since the account cookie was deleted, it holds no *description*
 * of one either. So what these examples pin down is the whole of its session
 * handling, which is one rule:
 *
 *   401 → ask the BFF to refresh → renewed? retry once. refused? sign out.
 *
 * Three things follow that are each worth an example. It never refreshes
 * speculatively, because a refresh spends a token and doing that on page load
 * is what made two tabs opening at once look like theft. It never decides for
 * itself that a session is over, because only the BFF can see the refresh
 * cookie. And it distinguishes "refused" from "unreachable", because signing
 * somebody out over a dropped connection logs them out of a session that is
 * fine.
 */

const fetchMock = vi.fn();
const hardRedirect = vi.fn();

vi.mock("@/lib/navigate", () => ({
  hardRedirect: (path: string) => hardRedirect(path),
  signInPath: () => "/sign-in?next=%2Flinks",
}));

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const EXPIRED = () =>
  json({ error: { code: "token_expired", message: "Access token expired" } }, 401);
const SIGNED_OUT = () =>
  json({ error: { code: "unauthenticated", message: "Sign in required" } }, 401);
const RENEWED = () => json({ expires_in: 900 });
const LINKS = () => json({ links: [], pagination: { page: 1, per_page: 25, total: 0 } });

const refreshCalls = () =>
  fetchMock.mock.calls.filter(([url]) => String(url) === "/api/auth/refresh").length;

const apiCalls = () => fetchMock.mock.calls.filter(([url]) => String(url).includes("/api/v1/"));

beforeEach(() => {
  fetchMock.mockReset();
  hardRedirect.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("the API client", () => {
  it("sends the cookie and nothing else — there is no Authorization header to send", async () => {
    fetchMock.mockResolvedValueOnce(LINKS());

    await listLinks();

    const [, init] = apiCalls()[0];

    expect(init.credentials).toBe("include");
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
  });

  // The rule the cookie-backed access token exists for.
  it("does not refresh on an ordinary request, however many are made", async () => {
    // A fresh Response per call: a body can only be read once, so handing the
    // same object to three requests would fail on the second for a reason that
    // has nothing to do with the client.
    fetchMock.mockImplementation(() => Promise.resolve(LINKS()));

    await listLinks();
    await listLinks();
    await listLinks();

    expect(refreshCalls()).toBe(0);
    expect(apiCalls()).toHaveLength(3);
  });

  it("refreshes once and retries once when the token has expired", async () => {
    fetchMock
      .mockResolvedValueOnce(EXPIRED())
      .mockResolvedValueOnce(RENEWED())
      .mockResolvedValueOnce(LINKS());

    await listLinks();

    expect(refreshCalls()).toBe(1);
    expect(apiCalls()).toHaveLength(2);
    expect(hardRedirect).not.toHaveBeenCalled();
  });

  /*
   * The case the deleted account cookie used to get wrong.
   *
   * `unauthenticated` means no usable credential arrived — the access cookie
   * cleared while the refresh cookie survived, say. The old client consulted a
   * readable cookie to decide whether that was worth a refresh, and when that
   * cookie was the thing missing it concluded "signed out" and stranded a live
   * session. Only the BFF can see the refresh cookie, so only the BFF is asked.
   */
  it("refreshes on `unauthenticated` too, rather than deciding for itself", async () => {
    fetchMock
      .mockResolvedValueOnce(SIGNED_OUT())
      .mockResolvedValueOnce(RENEWED())
      .mockResolvedValueOnce(LINKS());

    await listLinks();

    expect(refreshCalls()).toBe(1);
    expect(hardRedirect).not.toHaveBeenCalled();
  });

  it("signs the person out when the BFF refuses the refresh", async () => {
    fetchMock.mockResolvedValueOnce(SIGNED_OUT()).mockResolvedValueOnce(SIGNED_OUT());

    await expect(listLinks()).rejects.toMatchObject({ code: "unauthenticated" });

    expect(refreshCalls()).toBe(1);
    expect(hardRedirect).toHaveBeenCalledWith("/sign-in?next=%2Flinks");
  });

  it("signs the person out when the retry is refused after a good rotation", async () => {
    fetchMock
      .mockResolvedValueOnce(EXPIRED())
      .mockResolvedValueOnce(RENEWED())
      .mockResolvedValueOnce(SIGNED_OUT());

    await expect(listLinks()).rejects.toMatchObject({ code: "unauthenticated" });

    expect(refreshCalls()).toBe(1);
    expect(apiCalls()).toHaveLength(2);
    expect(hardRedirect).toHaveBeenCalledTimes(1);
  });

  // Offline is not signed out. The cookies are untouched and the session is
  // fine; the next attempt on a working connection decides it properly.
  it("leaves the session alone when the refresh cannot be reached at all", async () => {
    fetchMock
      .mockResolvedValueOnce(EXPIRED())
      .mockRejectedValueOnce(new TypeError("Failed to fetch"));

    await expect(listLinks()).rejects.toMatchObject({ code: "token_expired" });

    expect(hardRedirect).not.toHaveBeenCalled();
  });

  it("spends one refresh for concurrent callers, not one each", async () => {
    let expired = 3;

    fetchMock.mockImplementation((url: string) => {
      if (url === "/api/auth/refresh") return Promise.resolve(RENEWED());

      if (expired > 0) {
        expired -= 1;

        return Promise.resolve(EXPIRED());
      }

      return Promise.resolve(LINKS());
    });

    await Promise.all([listLinks(), listLinks(), listLinks()]);

    expect(refreshCalls()).toBe(1);
  });

  it("surfaces the API's error code so the UI can branch on it", async () => {
    fetchMock.mockResolvedValueOnce(
      json({ error: { code: "blocked_domain", message: "Blocked" } }, 422),
    );

    await expect(listLinks()).rejects.toMatchObject({ code: "blocked_domain", status: 422 });
  });

  it("reports a 429 as rate limited even when it arrives with no envelope", async () => {
    fetchMock.mockResolvedValueOnce(new Response("", { status: 429 }));

    await expect(listLinks()).rejects.toMatchObject({ rateLimited: true });
  });
});

describe("the account", () => {
  it("comes from /me and not from anything stored in the browser", async () => {
    fetchMock.mockResolvedValueOnce(
      json({
        account: {
          id: "0198c0de-0000-7000-8000-000000000000",
          email: "you@acme.example",
          role: "creator",
          plan: "free",
          created_at: "2026-01-01T00:00:00Z",
        },
      }),
    );

    await expect(getAccount()).resolves.toMatchObject({
      account: { email: "you@acme.example", role: "creator" },
    });

    expect(String(apiCalls()[0][0])).toContain("/api/v1/me");
    expect(document.cookie).toBe("");
  });
});
