export type AccountRole = "creator" | "admin";

export type Account = {
  email: string;
  role: AccountRole;
};

export function isAdmin(account: Account | null): boolean {
  return account?.role === "admin";
}
