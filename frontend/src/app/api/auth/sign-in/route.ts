import { NextRequest } from "next/server";

import { apiRequest, forwardFailure, openSession, type TokenPair } from "@/lib/bff";

/**
 * `POST /api/auth/sign-in` — the browser's only sign-in surface (research.md D10).
 *
 * The form posts here rather than to Rails so that neither token reaches the
 * browser as a value. Both become httpOnly cookies; the body carries
 * `expires_in` and nothing else. Who signed in is not recorded anywhere on the
 * way through — `GET /api/v1/me` answers that.
 */
export async function POST(request: NextRequest) {
  const { email, password } = await request.json();

  const response = await apiRequest("/sessions", { email, password });

  if (!response.ok) return forwardFailure(response);

  return openSession((await response.json()) as TokenPair);
}
