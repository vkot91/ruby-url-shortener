"use client";

import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

/**
 * TanStack Query, scoped to the dashboard segment (research.md D15).
 *
 * Deliberately not mounted at the root. The only things in this product that
 * need a query cache are the click-count poll on the link list (T108, SC-009)
 * and the account the header draws — the redirect is a server response with no
 * React in it, the marketing page is static, and the auth forms are one-shot
 * mutations that own their own pending state. A provider at the root would
 * advertise this as the application's data layer, which it is not.
 *
 * The client is created inside a `useState` initialiser rather than at module
 * scope: a module-level client is shared across every request the Node process
 * handles, which on the server means one user's cached links being served to
 * the next.
 */
export function DashboardProviders({ children }: { children: React.ReactNode }) {
  const [queryClient] = React.useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // The counter is up to 30 seconds behind reality by design (SC-009,
            // D4), so treating a 30-second-old response as fresh matches what
            // the number actually means and keeps a tab switch from firing a
            // request that could not return anything new.
            staleTime: 30_000,
            // One retry, not the default three. A dashboard that spends four
            // attempts before showing "Couldn't load your links" leaves the
            // person looking at a spinner for the whole of it.
            retry: 1,
            refetchOnWindowFocus: false,
          },
        },
      }),
  );

  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}
