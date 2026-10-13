"use client";

import NextLink from "next/link";
import { MoreHorizontalIcon } from "lucide-react";

import { ClickCount } from "@/components/click-count";
import { CopyButton } from "@/components/copy-button";
import { ShortLink } from "@/components/short-link";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { TableCell, TableRow } from "@/components/ui/table";
import { formatCreatedAt, middleTruncate, splitShortUrl } from "@/lib/format";
import type { Link } from "@/lib/api";

/**
 * One row of the creator's link table (design.md §6.3, §7).
 *
 * Its counterpart `<AdminLinkRow>` (T094) is a separate component rather than
 * this one behind a flag. That is design.md P6 and FR-034 made structural: an
 * admin table that cannot show marketing statistics is one whose row component
 * has no clicks column to switch off.
 */
export function CreatorLinkRow({ link }: { link: Link }) {
  const { domain, code } = splitShortUrl(link.short_url);

  return (
    <TableRow className="hover:bg-accent">
      <TableCell className="w-[260px]">
        <span className="flex items-center gap-1">
          <ShortLink domain={domain} code={code} />

          <CopyButton value={link.short_url} label={`Copy ${domain}/${code}`} />
        </span>
      </TableCell>

      <TableCell className="text-body text-muted-foreground">
        {/* The full address as `title`, so middle truncation loses nothing. */}
        <span title={link.destination_url}>{middleTruncate(link.destination_url)}</span>
      </TableCell>

      <TableCell className="w-[120px] text-body-sm whitespace-nowrap text-muted-foreground">
        {/* The machine-readable timestamp stays in the markup even though the
            visible text is relative, so a screen reader or a copy-paste gets a
            date rather than "3 days ago". */}
        <time dateTime={link.created_at}>{formatCreatedAt(link.created_at)}</time>
      </TableCell>

      <TableCell className="w-[100px] text-right">
        <ClickCount value={link.clicks_count} />
      </TableCell>

      <TableCell className="w-[48px]">
        {/* Always rendered, never revealed on hover (design.md P2): an action
            that appears only under a pointer does not exist on a touch screen.
            Both destinations arrive with US3 — T080 and T081. */}
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <Button variant="ghost" size="icon" aria-label={`Actions for ${domain}/${code}`}>
                <MoreHorizontalIcon aria-hidden="true" />
              </Button>
            }
          />

          <DropdownMenuContent align="end">
            <DropdownMenuItem render={<NextLink href={`/links/${link.id}/edit`}>Edit</NextLink>} />
            <DropdownMenuItem render={<NextLink href={`/links/${link.id}`}>Delete</NextLink>} />
          </DropdownMenuContent>
        </DropdownMenu>
      </TableCell>
    </TableRow>
  );
}
