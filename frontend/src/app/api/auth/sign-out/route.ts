import { NextResponse } from "next/server";

import { apiRequest, closeSession, readRefreshToken } from "@/lib/bff";

/**
 * `POST /api/auth/sign-out` — revokes the refresh-token family and drops both
 * session cookies.
 *
 * Always 204, whatever Rails says. Signing out is something a person did, not a
 * request that can fail from their point of view: both cookies are gone, and
 * they were the whole of the session, so reporting an error would leave
 * somebody staring at a failure for an action that has already happened. Rails
 * answers 204 for an unknown token for the same reason.
 *
 * The access token already issued keeps working until it expires — the window
 * research.md D10 records and accepts.
 */
export async function POST() {
  const refreshToken = await readRefreshToken();

  if (refreshToken) {
    await apiRequest("/sessions", { refresh_token: refreshToken }, "DELETE");
  }

  return closeSession(new NextResponse(null, { status: 204 }));
}
