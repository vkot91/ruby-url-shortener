import { cn } from "@/lib/utils";

/**
 * design.md §6.3 and §6.7. No illustration — warmth in this product comes from
 * the palette and the copy, not from decoration.
 *
 * The two uses read very differently: an empty link list is a prompt, while an
 * empty moderation queue is the good outcome and must not look like an error.
 * That difference lives entirely in the copy the caller passes, which is why
 * this component carries no tone of its own.
 */
export function EmptyState({
  heading,
  description,
  action,
  className,
}: {
  heading: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center gap-3 px-8 py-16 text-center", className)}>
      <h2 className="text-h2 font-semibold text-foreground">{heading}</h2>

      {description && <p className="max-w-[42ch] text-body text-muted-foreground">{description}</p>}

      {action && <div className="pt-2">{action}</div>}
    </div>
  );
}
