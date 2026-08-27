import { cn } from "@/lib/utils";

// design.md P3: one integer per link, set as typography. No sparkline, no
// trend arrow — deep analytics are out of MVP scope and plan.md excludes a
// charting library, so nothing here may imply a trend line exists.
//
// design.md P4: T108 refetches every 30 seconds. Tabular figures plus a class
// list that does not vary with the value are what stop 9 → 10 → 100 from
// reflowing the column under a reader's eyes.
const COUNT_CLASSES = "font-mono text-metric font-semibold tabular-nums text-foreground";

export function ClickCount({ value, className }: { value: number; className?: string }) {
  return (
    <span data-testid="click-count" className={cn(COUNT_CLASSES, className)}>
      {value.toLocaleString("en-US")}
    </span>
  );
}
