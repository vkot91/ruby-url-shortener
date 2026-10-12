"use client";

import * as React from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { LoaderCircleIcon } from "lucide-react";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ApiError, type Link } from "@/lib/api";

/**
 * The destination-and-name form, shared by create (T070) and edit (T080).
 *
 * The schema and the error table below are the pieces §6.5 says the edit screen
 * reuses, so they live here rather than in the create page — a second copy
 * would be a second place for the six `error.code` values to fall out of step
 * with the API that sends them.
 */

const MAX_NAME_LENGTH = 120;

/**
 * Deliberately shallow. `z.url()` accepts far more than this product does, and
 * the checks that matter — the scheme, whether the host resolves to a private
 * address, whether it is one of our own codes, whether the domain is blocked —
 * need DNS and a blocklist and therefore happen in Rails (FR-006, FR-007).
 *
 * This exists to catch an empty field and obvious nonsense without a round
 * trip. Everything else arrives as an `error.code` and is rendered by the table
 * below, which is why that table is the load-bearing half of this file.
 */
export const linkSchema = z.object({
  destination_url: z
    .string()
    .trim()
    .min(1, "Enter a web address.")
    .pipe(z.url("That doesn't look like a web address. Check for typos.")),
  name: z
    .string()
    .trim()
    .max(MAX_NAME_LENGTH, `Keep the name under ${MAX_NAME_LENGTH} characters.`)
    .optional(),
});

export type LinkFormValues = z.infer<typeof linkSchema>;

/**
 * design.md §6.4's error table, verbatim.
 *
 * Five of the six codes attach to the Destination field, which is what makes
 * them field errors rather than a banner: each one is a statement about the
 * address that was typed, and the person's next action is to edit it. The
 * sixth, `link_limit_reached`, is not about the address at all — no edit to
 * this field can fix it — so it renders form-level and disables submit.
 */
const FIELD_ERRORS: Record<string, string> = {
  invalid_url: "That doesn't look like a web address. Check for typos.",
  unsupported_scheme: "Links must start with http:// or https://.",
  private_address:
    "That address points inside a private network, so it wouldn't work for your visitors.",
  self_referential: "That's already a Snip link. Share it directly instead.",
  blocked_domain: "That destination is on our blocked list and can't be shortened.",
};

const LIMIT_REACHED =
  "You've reached the 50-link limit on the free plan. Delete a link to make room.";

/**
 * FR-019's guarantee, restated for the person who just hit the hourly limit.
 * The second clause is required, not decorative: somebody refused at creation
 * needs to know the links they have already published are still working.
 */
const RATE_LIMITED =
  "You're creating links faster than the hourly limit allows. Try again shortly — your existing links are unaffected.";

export function LinkForm({
  defaultValues,
  submitLabel,
  onSubmit,
  onCancel,
}: {
  defaultValues?: Partial<LinkFormValues>;
  submitLabel: string;
  onSubmit: (values: LinkFormValues) => Promise<Link>;
  onCancel: () => void;
}) {
  const [formError, setFormError] = React.useState<string | null>(null);

  const {
    register,
    handleSubmit,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<LinkFormValues>({
    resolver: zodResolver(linkSchema),
    defaultValues: { destination_url: "", name: "", ...defaultValues },
  });

  const submit = handleSubmit(async (values) => {
    setFormError(null);

    try {
      await onSubmit({ ...values, name: values.name || undefined });
    } catch (error) {
      if (!(error instanceof ApiError)) {
        setFormError("Something went wrong. Try again.");

        return;
      }

      if (error.rateLimited) {
        setFormError(RATE_LIMITED);

        return;
      }

      if (error.code === "link_limit_reached") {
        setFormError(LIMIT_REACHED);

        return;
      }

      // An unrecognised code still reaches the person, carrying the API's own
      // message. Rendering nothing would leave a form that silently refuses to
      // submit, which is the worst of the available failures (design.md P5).
      setError("destination_url", {
        message: FIELD_ERRORS[error.code] ?? error.message,
      });
    }
  });

  const limitReached = formError === LIMIT_REACHED;

  return (
    <form onSubmit={submit} noValidate className="flex flex-col gap-5">
      {formError && (
        <p role="alert" className="rounded-lg bg-card p-3 text-body-sm text-destructive">
          {formError}
        </p>
      )}

      <div className="flex flex-col gap-2">
        <Label htmlFor="destination_url">Destination URL</Label>

        <Input
          id="destination_url"
          inputMode="url"
          autoFocus
          disabled={isSubmitting}
          className="font-mono text-code"
          aria-invalid={Boolean(errors.destination_url)}
          aria-describedby={
            errors.destination_url ? "destination_url-error" : "destination_url-help"
          }
          {...register("destination_url")}
        />

        {errors.destination_url ? (
          <p id="destination_url-error" className="text-body-sm text-destructive">
            {errors.destination_url.message}
          </p>
        ) : (
          <p id="destination_url-help" className="text-body-sm text-muted-foreground">
            The address people should land on.
          </p>
        )}
      </div>

      <div className="flex flex-col gap-2">
        <Label htmlFor="name">Name (optional)</Label>

        <Input
          id="name"
          disabled={isSubmitting}
          aria-invalid={Boolean(errors.name)}
          aria-describedby={errors.name ? "name-error" : "name-help"}
          {...register("name")}
        />

        {errors.name ? (
          <p id="name-error" className="text-body-sm text-destructive">
            {errors.name.message}
          </p>
        ) : (
          <p id="name-help" className="text-body-sm text-muted-foreground">
            Only you see this.
          </p>
        )}
      </div>

      <div className="flex items-center gap-3">
        <Button type="submit" size="lg" disabled={isSubmitting || limitReached}>
          {isSubmitting && <LoaderCircleIcon aria-hidden="true" className="animate-spin" />}
          {submitLabel}
        </Button>

        <Button type="button" variant="ghost" size="lg" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
