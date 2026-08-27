import { AppShell } from "@/components/app-shell";
import type { Account } from "@/lib/account";

const account: Account | null = null;

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <AppShell account={account}>{children}</AppShell>;
}
