import Link from "next/link";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { isAdmin, type Account } from "@/lib/account";

/**
 * design.md §6.1. FR-003 is satisfied structurally: a creator's document
 * contains no admin control at all, not a disabled one. A disabled item still
 * tells a creator the admin area exists and where it lives.
 */
export function AccountMenu({ account }: { account: Account | null }) {
  if (!account) {
    return <Button variant="ghost" size="sm" render={<Link href="/sign-in">Sign in</Link>} />;
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button variant="ghost" size="sm" aria-label="Account menu">
            <span className="max-w-[200px] truncate text-body-sm text-muted-foreground">
              {account.email}
            </span>
          </Button>
        }
      />
      <DropdownMenuContent align="end">
        <DropdownMenuLabel className="text-body-sm text-muted-foreground">
          {account.email}
        </DropdownMenuLabel>
        <DropdownMenuSeparator />

        {isAdmin(account) && <DropdownMenuItem render={<Link href="/admin/reports">Admin</Link>} />}

        <DropdownMenuItem render={<Link href="/sign-out">Sign out</Link>} />
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
