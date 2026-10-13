"use client";

import * as React from "react";
import NextLink from "next/link";

import { CreatorLinkRow } from "@/components/creator-link-row";
import { EmptyState } from "@/components/empty-state";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { PER_PAGE, useLinks } from "@/app/(dashboard)/links/use-links";

/** FR-004, and Account::FREE_LINK_LIMIT in Rails. The two must agree. */
const FREE_LINK_LIMIT = 50;

/** design.md §6.3: the usage line turns destructive as the limit comes close. */
const WARNING_THRESHOLD = 45;

const SKELETON_ROWS = 5;

const COLUMNS = ["Short link", "Destination", "Created", "Clicks", ""];

export function LinkList() {
  const [page, setPage] = React.useState(1);

  const { data, isPending, isError, refetch } = useLinks(page);

  const links = data?.links ?? [];
  const total = data?.pagination.total ?? 0;

  const atLimit = total >= FREE_LINK_LIMIT;
  const lastPage = Math.max(1, Math.ceil(total / PER_PAGE));

  return (
    <div className="flex flex-col gap-6">
      <header className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-h1 font-semibold text-foreground">Your links</h1>

          {/* Rendered from the pagination total rather than from the page, so it
              counts the account's links and not the ones currently on screen. */}
          {data && (
            <p
              className={
                total >= WARNING_THRESHOLD
                  ? "mt-1 text-body-sm text-destructive"
                  : "mt-1 text-body-sm text-muted-foreground"
              }
            >
              {total} of {FREE_LINK_LIMIT} links used
            </p>
          )}
        </div>

        {/* design.md §6.4's preemptive treatment: at the limit the button is
            disabled with the reason in a tooltip, rather than opening a form
            that cannot succeed. The form-level error still exists there, because
            the count can change in another tab. */}
        {atLimit ? (
          <Tooltip>
            <TooltipTrigger
              render={
                <span>
                  <Button disabled>New link</Button>
                </span>
              }
            />
            <TooltipContent>
              You have reached the {FREE_LINK_LIMIT}-link limit on the free plan. Delete a link to
              make room.
            </TooltipContent>
          </Tooltip>
        ) : (
          <Button render={<NextLink href="/links/new">New link</NextLink>} />
        )}
      </header>

      {isError ? (
        <ErrorPanel onRetry={() => refetch()} />
      ) : (
        <div className="overflow-hidden rounded-xl border bg-card">
          <Table>
            <TableHeader>
              <TableRow className="bg-muted hover:bg-muted">
                {COLUMNS.map((column) => (
                  <TableHead
                    key={column}
                    className={column === "Clicks" ? "text-right" : undefined}
                  >
                    {column || <span className="sr-only">Actions</span>}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>

            <TableBody>
              {isPending && <SkeletonRows />}

              {!isPending && links.map((link) => <CreatorLinkRow key={link.id} link={link} />)}
            </TableBody>
          </Table>

          {!isPending && links.length === 0 && (
            <EmptyState
              heading="No links yet"
              description="Shorten your first address and it will show up here with its click count."
              action={
                <Button render={<NextLink href="/links/new">Create your first link</NextLink>} />
              }
            />
          )}
        </div>
      )}

      {total > PER_PAGE && (
        <Pagination
          page={page}
          lastPage={lastPage}
          total={total}
          shown={links.length}
          onChange={setPage}
        />
      )}
    </div>
  );
}

/**
 * Five rows at the height of a real one, so the table does not jump when the
 * data lands (design.md §6.3).
 */
function SkeletonRows() {
  return (
    <>
      {Array.from({ length: SKELETON_ROWS }, (_, row) => (
        <TableRow key={row}>
          {COLUMNS.map((column) => (
            <TableCell key={column} className="py-3">
              <Skeleton className="h-5 w-full" />
            </TableCell>
          ))}
        </TableRow>
      ))}
    </>
  );
}

/**
 * The header row above stays usable while this is on screen — somebody whose
 * list failed to load can still create a link, and telling them otherwise would
 * make a read failure look like an outage.
 */
function ErrorPanel({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="flex flex-col items-start gap-3 rounded-xl border bg-card p-6">
      <p role="alert" className="text-body text-destructive">
        Couldn&apos;t load your links.
      </p>

      <Button variant="secondary" onClick={onRetry}>
        Try again
      </Button>
    </div>
  );
}

function Pagination({
  page,
  lastPage,
  total,
  shown,
  onChange,
}: {
  page: number;
  lastPage: number;
  total: number;
  shown: number;
  onChange: (page: number) => void;
}) {
  const first = (page - 1) * PER_PAGE + 1;

  return (
    <nav aria-label="Pagination" className="flex items-center justify-between">
      <p className="text-body-sm text-muted-foreground">
        Showing {first}–{first + shown - 1} of {total}
      </p>

      <div className="flex gap-2">
        <Button variant="outline" disabled={page <= 1} onClick={() => onChange(page - 1)}>
          Previous
        </Button>

        <Button variant="outline" disabled={page >= lastPage} onClick={() => onChange(page + 1)}>
          Next
        </Button>
      </div>
    </nav>
  );
}
