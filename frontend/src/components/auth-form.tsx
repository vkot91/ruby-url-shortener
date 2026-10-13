"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { EyeIcon, EyeOffIcon, LoaderCircleIcon } from "lucide-react";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ApiError, signIn, signUp } from "@/lib/api";

/**
 * Sign-in and sign-up (design.md §6.2). Two screens, one component, because the
 * only differences are the button label, the link underneath, and which client
 * function runs — and FR-036 requires their failure copy to be identical, which
 * is a guarantee much easier to keep in one file than in two.
 */

/**
 * Twelve characters, matching the API's minimum (contracts/openapi.yaml). It is
 * checked here as well as there so that a password too short to be accepted
 * says so before a round trip, not because the client's check is the one that
 * counts — the server's is.
 */
const MINIMUM_PASSWORD_LENGTH = 12;

const schema = z.object({
  email: z.email("Enter an email address."),
  password: z
    .string()
    .min(MINIMUM_PASSWORD_LENGTH, `Use at least ${MINIMUM_PASSWORD_LENGTH} characters.`),
});

type Credentials = z.infer<typeof schema>;

/**
 * FR-036's central copy decision, and the reason this string is a constant.
 *
 * A refused attempt must not reveal whether an email address is registered, so
 * sign-in and sign-up show the *same* sentence for every refusal: wrong
 * password, unknown address, and — on sign-up — an address that already has an
 * account. There is deliberately no field-level "email already taken" anywhere
 * in this component. Rails goes to the trouble of making the two cases cost the
 * same time and return the same body; a form that then said which one it was
 * would give it all back.
 */
const REFUSED = "That email and password combination didn't work.";
const RATE_LIMITED = "Too many attempts. Try again in a few minutes.";

export function AuthForm({ mode }: { mode: "sign-in" | "sign-up" }) {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [formError, setFormError] = React.useState<string | null>(null);
  const [rateLimited, setRateLimited] = React.useState(false);
  const [passwordVisible, setPasswordVisible] = React.useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<Credentials>({ resolver: zodResolver(schema) });

  const submit = handleSubmit(async (credentials) => {
    setFormError(null);

    try {
      await (mode === "sign-in" ? signIn(credentials) : signUp(credentials));

      // Where the guard in src/middleware.ts sent them from, so signing in
      // finishes the journey they started. Only a path on this origin is
      // honoured: `next` arrives from the URL bar, and following an absolute
      // one would turn the sign-in page into an open redirect.
      const next = searchParams.get("next");

      router.push(next?.startsWith("/") && !next.startsWith("//") ? next : "/links");
    } catch (error) {
      // Every failure collapses to one of two messages. A 429 is distinguishable
      // from a refusal on purpose and only on purpose: it tells the person to
      // wait rather than to check their password, and it says nothing about
      // whether the address exists (Rails sends an identical body for both).
      const throttled = error instanceof ApiError && error.rateLimited;

      setRateLimited(throttled);
      setFormError(throttled ? RATE_LIMITED : REFUSED);
    }
  });

  const signingUp = mode === "sign-up";

  return (
    <div className="rounded-xl border bg-card p-8 shadow-sm">
      {/*
        The throttled state clears the moment either field is edited (design.md
        §6.2 keeps the fields enabled while disabling submit). A disabled button
        with no way back would strand somebody who mistyped their address on the
        one attempt that tripped the limit.
      */}
      <form
        onSubmit={submit}
        onChange={() => setRateLimited(false)}
        noValidate
        className="flex flex-col gap-4"
      >
        {formError && (
          <p role="alert" className="text-body-sm text-destructive">
            {formError}
          </p>
        )}

        <div className="flex flex-col gap-2">
          <Label htmlFor="email">Email</Label>

          <Input
            id="email"
            type="email"
            autoComplete="email"
            autoFocus
            disabled={isSubmitting}
            aria-invalid={Boolean(errors.email)}
            aria-describedby={errors.email ? "email-error" : undefined}
            {...register("email")}
          />

          {errors.email && (
            <p id="email-error" className="text-body-sm text-destructive">
              {errors.email.message}
            </p>
          )}
        </div>

        <div className="flex flex-col gap-2">
          <Label htmlFor="password">Password</Label>

          <div className="relative">
            <Input
              id="password"
              type={passwordVisible ? "text" : "password"}
              autoComplete={signingUp ? "new-password" : "current-password"}
              disabled={isSubmitting}
              aria-invalid={Boolean(errors.password)}
              aria-describedby={errors.password ? "password-error" : undefined}
              className="pr-10"
              {...register("password")}
            />

            {/*
              Sign-up gets a visibility toggle instead of a confirm-password
              field (design.md §6.2): letting somebody read what they typed
              prevents the mistake that a second field only detects.
            */}
            {signingUp && (
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                aria-label={passwordVisible ? "Hide password" : "Show password"}
                aria-pressed={passwordVisible}
                onClick={() => setPasswordVisible((visible) => !visible)}
                className="absolute inset-y-0 right-1 my-auto"
              >
                {passwordVisible ? (
                  <EyeOffIcon aria-hidden="true" />
                ) : (
                  <EyeIcon aria-hidden="true" />
                )}
              </Button>
            )}
          </div>

          {errors.password && (
            <p id="password-error" className="text-body-sm text-destructive">
              {errors.password.message}
            </p>
          )}
        </div>

        <Button
          type="submit"
          size="lg"
          disabled={isSubmitting || rateLimited}
          className="mt-2 w-full"
        >
          {isSubmitting && <LoaderCircleIcon aria-hidden="true" className="animate-spin" />}
          {signingUp ? "Create account" : "Sign in"}
        </Button>
      </form>

      <p className="mt-6 text-center text-body-sm text-muted-foreground">
        {signingUp ? "Already have an account? " : "No account yet? "}

        <Link
          href={signingUp ? "/sign-in" : "/sign-up"}
          className="text-primary underline-offset-4 hover:underline"
        >
          {signingUp ? "Sign in" : "Create one"}
        </Link>
      </p>
    </div>
  );
}
