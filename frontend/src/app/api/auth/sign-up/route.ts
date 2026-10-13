import { NextRequest } from "next/server";

import { apiRequest, forwardFailure, openSession, type TokenPair } from "@/lib/bff";

/**
 * `POST /api/auth/sign-up` — registration, which signs the new account in.
 *
 * Rails opens the first refresh-token family as part of creating the account
 * (FR-001), so there is no second round trip and no window in which somebody
 * has an account but no session.
 */
export async function POST(request: NextRequest) {
  const { email, password } = await request.json();

  const response = await apiRequest("/registrations", { email, password });

  if (!response.ok) return forwardFailure(response);

  return openSession((await response.json()) as TokenPair, { status: 201 });
}
