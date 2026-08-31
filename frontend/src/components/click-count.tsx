import { cn } from "@/lib/utils";

const COUNT_CLASSES = "font-mono text-metric font-semibold tabular-nums text-foreground";

export function ClickCount({ value, className }: { value: number; className?: string }) {
  return (
    <span data-testid="click-count" className={cn(COUNT_CLASSES, className)}>
      {value.toLocaleString("en-US")}
    </span>
  );
}
