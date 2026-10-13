"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

import { signOut } from "@/lib/api";

/**
 * The destination of the account menu's Sign out item (design.md §6.1).
 *
 * A page rather than a link straight at `/api/auth/sign-out`, because the
 * handler answers POST only: a sign-out reachable by GET is one any page on the
 * internet can trigger with an image tag, and `SameSite=Lax` sends the cookies
 * on exactly that kind of top-level navigation.
 */
export default function SignOutPage() {
  const router = useRouter();

  React.useEffect(() => {
    signOut().finally(() => router.replace("/sign-in"));
  }, [router]);

  return <p className="text-center text-body-sm text-muted-foreground">Signing out…</p>;
}
