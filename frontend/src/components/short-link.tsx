import { cn } from "@/lib/utils";

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
