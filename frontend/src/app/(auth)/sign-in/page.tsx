import { Suspense } from "react";
import type { Metadata } from "next";

import { AuthForm } from "@/components/auth-form";

export const metadata: Metadata = { title: "Sign in · Snip" };

/**
 * The Suspense boundary is required, not decorative: `<AuthForm>` reads the
 * `next` query parameter that src/middleware.ts sets, and a component reading
 * search params cannot be prerendered without one. Without it this page is
 * rendered on every request instead of being served as static HTML.
 */
export default function SignInPage() {
  return (
    <Suspense>
      <AuthForm mode="sign-in" />
    </Suspense>
  );
}
