/**
 * The browser's client for the Rails API (research.md D10).
 *
 * It holds no credential. Both tokens are httpOnly cookies the BFF set, so this
 * file never sees either one — `credentials: "include"` is the whole of its
 * authentication, and there is no variable here for an XSS to read or for a
 * page reload to lose.
 *
 * That last part is the point of the arrangement. When the access token lived
 * in a module variable it died with the page, so every reload spent a refresh
 * token to mint another — not a security property, a consequence of where the
 * value was kept, and one that made two tabs opening at once look to the server
 * like token theft. Now a refresh happens when the token has actually expired
 * and at no other time.
 *
 * The rule, in full, and it is the whole of the client's session handling:
 *
 *   401 → ask the BFF to refresh → succeeded? retry once. Refused? sign out.
 *
 * There is no fourth branch and nothing to consult before entering it. Whether
 * a refresh token exists is a question only the BFF can answer — the cookie
 * holding it is httpOnly, so this file could not read it if it wanted to — and
 * `POST /api/auth/refresh` answers it directly, with
 * 401 and cleared cookies when there is nothing to spend. An earlier version
 * kept a readable cookie here so the client could guess at that answer before
 * asking. Guessing was the bug: it was a second copy of the session's
 * existence, written once at sign-in, and it could be wrong in both directions.
 */

import type { Account } from "@/lib/account";
import { hardRedirect, signInPath } from "@/lib/navigate";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

export type Link = {
  id: string;
  code: string;
  short_url: string;
  destination_url: string;
  name: string | null;
  clicks_count: number;
  created_at: string;
};

export type Pagination = {
  page: number;
  per_page: number;
  total: number;
};

export type LinkList = {
  links: Link[];
  pagination: Pagination;
};

/**
 * The codes the UI branches on. Everything else is rendered from `message`, so
 * an unfamiliar code degrades to a readable error rather than to a blank panel
 * (design.md P5).
 */
export type ErrorCode =
  | "invalid_url"
  | "unsupported_scheme"
  | "private_address"
  | "self_referential"
  | "blocked_domain"
  | "link_limit_reached"
  | "invalid_credentials"
  | "validation_failed"
  | "parameter_missing"
  | "token_expired"
  | "unauthenticated"
  | "not_found"
  | "rate_limited"
  | (string & {});

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;

  constructor(code: ErrorCode, message: string, status: number) {
    super(message);

    this.name = "ApiError";
    this.code = code;
    this.status = status;
  }

  /**
   * The status rather than the code, because a 429 can reach the client from
   * outside the application — a proxy, or a load balancer shedding traffic —
   * and a client that only recognised `rate_limited` would tell somebody being
   * throttled that something went wrong.
   */
  get rateLimited() {
    return this.status === 429;
  }
}

/**
 * Asks the BFF to mint a new access cookie from the httpOnly refresh cookie.
 *
 * No precondition is checked here, deliberately. The BFF holds the refresh
 * cookie and is the only thing that can see whether one exists; it answers 401
 * and clears the session when there is none, which is the same answer this
 * would have produced by guessing, arrived at by knowing.
 *
 * Concurrent callers share one in-flight request. Two tabs are a separate
 * matter and cannot be coordinated from here at all; that race is answered on
 * the server by the rotation grace window in `Auth::RefreshTokens`.
 */
type RefreshOutcome = "renewed" | "refused" | "unreachable";

let inFlightRefresh: Promise<RefreshOutcome> | null = null;

function refreshAccessToken(): Promise<RefreshOutcome> {
  inFlightRefresh ??= (async () => {
    try {
      const response = await fetch("/api/auth/refresh", {
        method: "POST",
        credentials: "include",
      });

      return response.ok ? "renewed" : "refused";
    } catch {
      // Three outcomes rather than two, because a network failure is not an
      // ended session and must not be treated as one. Collapsing them signs
      // somebody out because their train went into a tunnel — and the cookies
      // are still there, so it signs them out of a session that was fine.
      return "unreachable";
    } finally {
      inFlightRefresh = null;
    }
  })();

  return inFlightRefresh;
}

/**
 * The end of a session, as the browser experiences it.
 *
 * The cookies are already gone — the BFF cleared them as part of refusing the
 * refresh — so this is only the navigation. It is a full page load rather than
 * a router push because every cache in the tree was built on a credential that
 * no longer exists (see `src/lib/navigate.ts`).
 */
function endSession() {
  hardRedirect(signInPath());
}

async function failure(response: Response): Promise<ApiError> {
  const fallback = response.status === 429 ? "rate_limited" : "request_failed";

  try {
    const body = (await response.json()) as { error?: { code?: string; message?: string } };

    return new ApiError(
      body.error?.code ?? fallback,
      body.error?.message ?? "Something went wrong.",
      response.status,
    );
  } catch {
    return new ApiError(fallback, "Something went wrong.", response.status);
  }
}

function send(path: string, init: RequestInit) {
  return fetch(`${API_URL}/api/v1${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...init.headers },
    // The credential, and the only one. The browser attaches the access cookie
    // because the BFF scoped it to a domain both origins share; Rails allows it
    // across the origin boundary because CORS is configured with
    // `credentials: true` against this one named origin.
    credentials: "include",
    cache: "no-store",
  });
}

/**
 * One authenticated call, with a refresh around it when the API refuses it.
 *
 * The request goes out first, always. There is no "do I have a token" question
 * to ask — the browser attaches the cookie or it does not, and Rails is the
 * only thing that can say whether what arrived was any good.
 *
 * Every 401 is treated the same way, and that is a simplification with a
 * reason behind it. Rails distinguishes `token_expired` from `unauthenticated`,
 * and that distinction is real and worth keeping in the API; but from here both
 * mean "the credential that went out was not accepted", and both have the same
 * remedy — spend a refresh token if there is one. Branching on the code meant
 * deciding *locally* that `unauthenticated` was hopeless, which stranded a live
 * session whenever the access cookie went missing while the refresh cookie
 * survived.
 *
 * A refused refresh is the end of the session. Rails has said the refresh token
 * is unknown, expired, revoked, or replayed; none of those recover, and a
 * client that kept retrying would loop against an endpoint that is never going
 * to start saying yes. So the person is signed out, once, on the spot.
 */
async function authenticated(path: string, init: RequestInit = {}): Promise<Response> {
  const response = await send(path, init);

  if (response.status !== 401) return response;

  const outcome = await refreshAccessToken();

  // Nothing was decided. Report the original refusal and leave the session
  // alone — the next attempt, on a working connection, will decide it properly.
  if (outcome === "unreachable") throw await failure(response);

  if (outcome === "refused") {
    endSession();

    throw await failure(response);
  }

  const retried = await send(path, init);

  // A 401 immediately after a successful rotation is not a token problem any
  // more. The session is over — banned account, revoked family — and retrying
  // again would be a loop.
  if (retried.status === 401) {
    endSession();

    throw await failure(retried);
  }

  return retried;
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await authenticated(path, init);

  if (!response.ok) throw await failure(response);

  if (response.status === 204) return undefined as T;

  return (await response.json()) as T;
}

/** Sign-in, sign-up, and sign-out go through the BFF, not through `API_URL`. */
async function bff<T>(path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "include",
  });

  if (!response.ok) throw await failure(response);

  if (response.status === 204) return undefined as T;

  return (await response.json()) as T;
}

type Credentials = { email: string; password: string };

/**
 * All three return nothing. The session is entirely in cookies the BFF wrote,
 * so there is no token to hand back and nothing here to store — which is what
 * makes "signed in" a fact about the browser rather than about this module's
 * state.
 */
export async function signIn(credentials: Credentials) {
  await bff<void>("/api/auth/sign-in", credentials);
}

export async function signUp(credentials: Credentials) {
  await bff<void>("/api/auth/sign-up", credentials);
}

export async function signOut() {
  await bff<void>("/api/auth/sign-out");
}

/**
 * Who is signed in, from the one place that knows.
 *
 * This used to be read from a cookie the BFF wrote at sign-in, which was wrong
 * twice over: it put a person's address in a cookie attached to requests that
 * had no use for it, and it froze the answer at the moment the session opened,
 * so a corrected address or a granted role stayed invisible until the next
 * sign-in.
 *
 * `role` is for deciding whether to draw the admin link and for nothing else.
 * Every `/admin/*` endpoint re-derives it from the verified access token, so a
 * browser that talked itself into `admin` reaches responses that 403 (FR-003).
 */
export function getAccount() {
  return request<{ account: Account }>("/me");
}

export function listLinks({ page = 1, perPage = 25 } = {}) {
  return request<LinkList>(`/links?page=${page}&per_page=${perPage}`);
}

export function getLink(id: string) {
  return request<Link>(`/links/${id}`);
}

export function createLink(body: { destination_url: string; name?: string }) {
  return request<Link>("/links", { method: "POST", body: JSON.stringify(body) });
}
