"use client";

import Link from "next/link";

import { AccountMenu } from "@/components/account-menu";
import { ThemeToggle } from "@/components/theme-toggle";
import { useAccount } from "@/lib/use-account";

/**
 * The dashboard chrome.
 *
 * A client component so the header can read the account out of the query cache
 * — which the layout has already seeded from the server, so this renders with a
 * name in it on the first pass rather than filling in afterwards. The query is
 * what covers the one case the server cannot: an access token that had already
 * aged out when the page was requested, where refreshing means setting cookies
 * and only the browser's own request can do that.
 */
export function AppShell({ children }: { children: React.ReactNode }) {
  const { account, isPending } = useAccount();

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

            {/*
              An empty slot rather than the menu's signed-out state while the
              account is still being fetched. Middleware only lets a session
              through, so "Sign in" here would never be true — it would be a
              flash of the wrong answer on the one path where the server could
              not answer: an access token that had expired before the page was
              requested, which the browser is in the middle of refreshing.
            */}
            {isPending ? (
              <div className="h-8 w-[120px]" aria-hidden />
            ) : (
              <AccountMenu account={account} />
            )}
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[1120px] px-8 pt-8 pb-16">{children}</main>
    </div>
  );
}
