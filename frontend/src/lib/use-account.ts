"use client";

import { useQuery } from "@tanstack/react-query";

import { getAccount } from "@/lib/api";
import type { Account } from "@/lib/account";

/** Shared so the layout can seed this exact entry from its server-side fetch. */
export const ACCOUNT_QUERY_KEY = ["account"] as const;

/**
 * Who is signed in, from `GET /api/v1/me`.
 *
 * Usually resolved before it is ever called: the dashboard layout fetches the
 * same thing on the server and seeds the cache with it, so the first render
 * already has an address to put in the header. The query still exists for the
 * case the server could not answer — an access token that had aged out by the
 * time the page was requested, which a server component cannot refresh and this
 * can.
 *
 * `staleTime: Infinity` because an address and a role do not change while
 * somebody is looking at a page, and a background refetch of them would be a
 * request per tab focus buying nothing. A change of either lands at the next
 * full load, which is also when a new access token would have carried it.
 */
export function useAccount() {
  const { data, isPending } = useQuery<Account>({
    queryKey: ACCOUNT_QUERY_KEY,
    queryFn: async () => (await getAccount()).account,
    staleTime: Infinity,
    retry: false,
  });

  return { account: data ?? null, isPending };
}
