import Link from "next/link";

import { AccountMenu } from "@/components/account-menu";
import { ThemeToggle } from "@/components/theme-toggle";
import type { Account } from "@/lib/account";

// design.md §6.1. No sidebar: four screens do not justify persistent
// navigation, which is why the sidebar tokens in globals.css go unused.
export function AppShell({
  account,
  children,
}: {
  account: Account | null;
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-background">
      <header className="sticky top-0 z-40 border-b bg-card">
        <div className="mx-auto flex h-16 max-w-[1120px] items-center justify-between px-8">
          <Link
            href="/links"
            className="text-h2 font-semibold text-foreground transition-colors hover:text-primary-hover"
          >
            Snip
          </Link>

          <div className="flex items-center gap-2">
            <ThemeToggle />
            <AccountMenu account={account} />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[1120px] px-8 pt-8 pb-16">{children}</main>
    </div>
  );
}
