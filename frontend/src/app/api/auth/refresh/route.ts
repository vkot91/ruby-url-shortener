import { NextResponse } from "next/server";

import {
  apiRequest,
  closeSession,
  forwardFailure,
  openSession,
  readRefreshToken,
  type TokenPair,
} from "@/lib/bff";

/**
 * `POST /api/auth/refresh` — the only way a browser session outlives an access
 * token's fifteen minutes (research.md D10).
 *
 * Takes no body. The credential is the httpOnly cookie, which the browser sends
 * and cannot read; accepting a refresh token in the request body instead would
 * hand every caller a way to use one it had somehow obtained, which is the
 * arrangement the cookie exists to prevent.
 *
 * Rotation is Rails' half: the presented token is spent and a successor comes
 * back, so the cookie is rewritten on every success. A failure closes the
 * session, since a refresh token Rails has refused is never going to work again
 * — most importantly after reuse detection, where the whole family has just
 * been revoked and leaving the cookies in place would mean retrying a dead
 * session on every page load.
 */
export async function POST() {
  const refreshToken = await readRefreshToken();

  if (!refreshToken) {
    return closeSession(
      NextResponse.json(
        { error: { code: "unauthenticated", message: "Sign in required" } },
        { status: 401 },
      ),
    );
  }

  const response = await apiRequest("/auth/refresh", { refresh_token: refreshToken });

  if (!response.ok) return closeSession(await forwardFailure(response));

  return openSession((await response.json()) as TokenPair);
}
