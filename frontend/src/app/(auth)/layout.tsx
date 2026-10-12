import Link from "next/link";

/**
 * design.md §6.1 gives the dashboard a header; §6.2 deliberately does not give
 * one to sign-in. A person who is not signed in has no account menu to open and
 * nothing to navigate to, so the wordmark stands alone above the card and is
 * the only chrome on the screen.
 */
export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col items-center bg-background px-4 pt-12 pb-16 sm:justify-center sm:pt-0">
      <div className="mt-12 w-full max-w-[400px] sm:mt-0">
        <div className="mb-6 text-center">
          <Link href="/" className="text-display font-semibold text-foreground">
            Snip
          </Link>

          <p className="mt-2 text-body-sm text-muted-foreground">
            Short links that keep working after you publish them.
          </p>
        </div>

        {children}
      </div>
    </div>
  );
}
