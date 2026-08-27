import { AppShell } from "@/components/app-shell";
import type { Account } from "@/lib/account";

// The signed-in account comes from the BFF session once T118 lands. Until
// then the shell renders its signed-out branch, which is a real state it has
// to handle anyway — an expired session reaches exactly this code path.
const account: Account | null = null;

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <AppShell account={account}>{children}</AppShell>;
}
