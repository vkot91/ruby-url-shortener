"use client";

import * as React from "react";
import { CheckIcon, CopyIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const CONFIRMATION_MS = 2_000;

/**
 * design.md P2. The confirmation is a state this button holds for two seconds,
 * not a toast: a confirmation that fades can be missed, and SC-003 gives a
 * first-time user two minutes to get a working link without instruction.
 *
 * It is also never hover-revealed — hover does not exist on touch, and a large
 * share of link sharing happens from a phone.
 */
export function CopyButton({
  value,
  label,
  className,
}: {
  value: string;
  label: string;
  className?: string;
}) {
  const [copied, setCopied] = React.useState(false);
  const timeout = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  React.useEffect(() => {
    return () => {
      if (timeout.current) clearTimeout(timeout.current);
    };
  }, []);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value);
    } catch {
      // Clipboard access can be refused (insecure context, denied permission).
      // Claiming success then would be a lie the user acts on, so leave the
      // button in its rest state.
      return;
    }

    setCopied(true);

    // Clicking again mid-confirmation restarts the two seconds rather than
    // inheriting the remainder of the previous one.
    if (timeout.current) clearTimeout(timeout.current);

    timeout.current = setTimeout(() => setCopied(false), CONFIRMATION_MS);
  };

  return (
    <>
      <Button
        type="button"
        variant="ghost"
        size="icon"
        aria-label={copied ? "Copied" : label}
        onClick={copy}
        className={cn("transition-colors duration-150", copied && "text-success", className)}
      >
        {copied ? <CheckIcon aria-hidden="true" /> : <CopyIcon aria-hidden="true" />}
      </Button>

      {/* Announced rather than only shown: the swap is a color and an icon,
          and design.md §9 forbids color as the only signal. */}
      <span aria-live="polite" className="sr-only">
        {copied ? "Copied" : ""}
      </span>
    </>
  );
}
