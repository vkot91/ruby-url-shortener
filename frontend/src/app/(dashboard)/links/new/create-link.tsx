"use client";

import * as React from "react";
import NextLink from "next/link";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeftIcon, CheckIcon, CopyIcon } from "lucide-react";

import { LinkForm } from "@/components/link-form";
import { ShortLink } from "@/components/short-link";
import { Button } from "@/components/ui/button";
import { createLink, type Link } from "@/lib/api";
import { splitShortUrl } from "@/lib/format";

/**
 * design.md §6.4 — create a link.
 *
 * The screen's goal is not "a link exists"; it is "the link is on the person's
 * clipboard". That is why success replaces the form in place rather than
 * navigating to the list: a redirect to the table would put the thing they came
 * to copy in a 260px cell behind an icon button, one screen away from where
 * they were looking (SC-003).
 */
export function CreateLink() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [created, setCreated] = React.useState<Link | null>(null);

  const submit = React.useCallback(
    async (values: { destination_url: string; name?: string }) => {
      const link = await createLink(values);

      // The list and its usage line are now both wrong by one. Invalidating
      // rather than writing into the cache keeps the count authoritative: the
      // pagination total comes from the server, and a link created in another
      // tab would make any local arithmetic here quietly wrong.
      await queryClient.invalidateQueries({ queryKey: ["links"] });

      setCreated(link);

      return link;
    },
    [queryClient],
  );

  return (
    <div className="mx-auto flex w-full max-w-[640px] flex-col gap-4">
      <Button
        variant="ghost"
        size="sm"
        className="self-start"
        render={
          <NextLink href="/links">
            <ArrowLeftIcon aria-hidden="true" />
            Back to links
          </NextLink>
        }
      />

      <div className="rounded-xl border bg-card p-8 shadow-sm">
        {created ? (
          <SuccessPanel link={created} onCreateAnother={() => setCreated(null)} />
        ) : (
          <LinkForm
            submitLabel="Create link"
            onSubmit={submit}
            onCancel={() => router.push("/links")}
          />
        )}
      </div>
    </div>
  );
}

const CONFIRMATION_MS = 2_000;

/**
 * Not `<CopyButton>`. That component is a ghost icon button sized for a table
 * cell; here the same action is the largest control on the screen, because
 * copying is what the whole screen was for (design.md P2, §6.4). The two-second
 * confirmation and the `aria-live` announcement are the same, and they are
 * repeated here rather than parameterised into `<CopyButton>` — a shared
 * component with a "sometimes I am a full-width primary button" flag is two
 * components wearing one name.
 */
function SuccessPanel({ link, onCreateAnother }: { link: Link; onCreateAnother: () => void }) {
  const { domain, code } = splitShortUrl(link.short_url);

  const [copied, setCopied] = React.useState(false);
  const timeout = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  React.useEffect(() => {
    return () => {
      if (timeout.current) clearTimeout(timeout.current);
    };
  }, []);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(link.short_url);
    } catch {
      return;
    }

    setCopied(true);

    if (timeout.current) clearTimeout(timeout.current);

    timeout.current = setTimeout(() => setCopied(false), CONFIRMATION_MS);
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-2">
        <p className="text-body-sm text-muted-foreground">Your link is ready</p>

        <ShortLink domain={domain} code={code} className="text-[20px]" />
      </div>

      <Button size="lg" onClick={copy} className="w-full">
        {copied ? <CheckIcon aria-hidden="true" /> : <CopyIcon aria-hidden="true" />}
        {copied ? "Copied" : "Copy link"}
      </Button>

      <span aria-live="polite" className="sr-only">
        {copied ? "Copied" : ""}
      </span>

      <div className="flex items-center gap-4 text-body-sm">
        <button
          type="button"
          onClick={onCreateAnother}
          className="text-primary underline-offset-4 hover:underline"
        >
          Create another
        </button>

        <NextLink href="/links" className="text-primary underline-offset-4 hover:underline">
          Back to links
        </NextLink>
      </div>
    </div>
  );
}
