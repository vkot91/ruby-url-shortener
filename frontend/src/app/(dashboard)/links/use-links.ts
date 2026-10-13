"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";

import { listLinks, type LinkList } from "@/lib/api";

/**
 * SC-009: the dashboard shows the count within 30 seconds of the click. The
 * server's half is asserted in backend/spec/integration/click_counting_spec.rb;
 * this interval is the client's half of the same number.
 *
 * It is not tuned to feel live. It is the largest interval that still meets the
 * criterion, which is the right choice for a number the API defines as up to 30
 * seconds stale anyway — polling faster would multiply requests without being
 * able to return anything newer.
 */
export const POLL_INTERVAL_MS = 30_000;

/** design.md §6.3: pagination appears only above this many links. */
export const PER_PAGE = 25;

export const linksQueryKey = (page: number) => ["links", page] as const;

export function useLinks(page: number) {
  return useQuery<LinkList>({
    queryKey: linksQueryKey(page),
    queryFn: () => listLinks({ page, perPage: PER_PAGE }),
    refetchInterval: POLL_INTERVAL_MS,
    // design.md P4: a background refetch changes the number and nothing else.
    // Without this, every poll would drop the table back to its loading state
    // and the page would flicker twice a minute — and paging forward would
    // blank the table between the click and the next response.
    placeholderData: keepPreviousData,
  });
}
