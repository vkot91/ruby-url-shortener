/**
 * The shape `GET /api/v1/me` returns (contracts/openapi.yaml, `Account`).
 *
 * It is a type and two predicates and deliberately nothing more. Nothing here
 * may be used to decide what somebody is allowed to do: this describes what the
 * API said about the account, and every endpoint re-derives authority from the
 * signed access token on its own request (FR-003). `isAdmin` decides whether a
 * menu item is drawn, and that is the whole of its authority.
 */
export type AccountRole = "creator" | "admin";

export type Account = {
  id: string;
  email: string;
  role: AccountRole;
  plan: "free";
  created_at: string;
};

export function isAdmin(account: Account | null | undefined): boolean {
  return account?.role === "admin";
}
