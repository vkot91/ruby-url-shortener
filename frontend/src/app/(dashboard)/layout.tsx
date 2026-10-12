import { AppShell } from "@/components/app-shell";
import { DashboardProviders } from "@/app/(dashboard)/providers";

/**
 * Deliberately not `async`, and it used to be.
 *
 * It awaited `GET /api/v1/me` here so the header would carry an address in the
 * first byte of HTML. Next.js is explicit about the cost of that: "A top-level
 * `await` on `cookies()`, `headers()`, or the DAL in a layout delays the first
 * streamed chunk for that segment and holds `{children}` behind that work"
 * (nextjs.org/docs/app/guides/authentication, Auth and streaming). The link
 * list was waiting on a request that only the account menu needed.
 *
 * So the account is fetched by the shell instead, from the browser, and the
 * header streams a placeholder until it arrives. That also happens to be the
 * only version that handles an access token which expired before the page was
 * requested: refreshing means writing cookies, a server component cannot, and
 * the browser can.
 *
 * There is no auth check here on purpose. The same guide warns that a layout
 * "does not control whether the rest of the route renders" and that checks
 * belong close to the data. Routing is `src/middleware.ts`; authorisation is
 * Rails, on every request, against a signed token.
 */
export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <DashboardProviders>
      <AppShell>{children}</AppShell>
    </DashboardProviders>
  );
}
