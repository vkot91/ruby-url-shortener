import { cn } from "@/lib/utils";

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
