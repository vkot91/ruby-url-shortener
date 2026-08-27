import { cn } from "@/lib/utils";

/**
 * design.md P1. The 7-character code is the object the product exists to
 * produce (FR-005), so it takes the foreground and the domain recedes. Every
 * screen that shows a short link goes through here — this is the one place
 * that hierarchy is expressed.
 */
export function ShortLink({
  domain,
  code,
  className,
}: {
  domain: string;
  code: string;
  className?: string;
}) {
  return (
    <span
      data-testid="short-link"
      className={cn("font-mono text-code font-medium whitespace-nowrap", className)}
    >
      <span data-testid="short-link-domain" className="text-muted-foreground">
        {domain}/
      </span>
      <span data-testid="short-link-code" className="text-foreground">
        {code}
      </span>
    </span>
  );
}
