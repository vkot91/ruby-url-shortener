"use client";

import * as React from "react";
import { MonitorIcon, MoonIcon, SunIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { applyTheme, isTheme, readStoredTheme, type Theme } from "@/lib/theme";

const OPTIONS: ReadonlyArray<{ value: Theme; label: string; Icon: typeof SunIcon }> = [
  { value: "system", label: "System", Icon: MonitorIcon },
  { value: "light", label: "Light", Icon: SunIcon },
  { value: "dark", label: "Dark", Icon: MoonIcon },
];

export function ThemeToggle() {
  // Starts at "system" on the server and on the first client render, then
  // syncs in an effect. The document class is already correct by then —
  // ThemeScript set it before paint — so this only catches up the control's
  // own label, never the page's appearance.
  const [theme, setTheme] = React.useState<Theme>("system");

  React.useEffect(() => {
    setTheme(readStoredTheme());
  }, []);

  React.useEffect(() => {
    if (theme !== "system") return;

    // Only while following the system does an OS change need to be tracked.
    const query = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => applyTheme("system");

    query.addEventListener("change", onChange);

    return () => query.removeEventListener("change", onChange);
  }, [theme]);

  const select = (value: string) => {
    if (!isTheme(value)) return;

    setTheme(value);
    applyTheme(value);
  };

  const active = OPTIONS.find((option) => option.value === theme) ?? OPTIONS[0];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button variant="ghost" size="icon" aria-label={`Theme: ${active.label}`}>
            <active.Icon aria-hidden="true" />
          </Button>
        }
      />
      <DropdownMenuContent align="end">
        <DropdownMenuRadioGroup value={theme} onValueChange={select}>
          {OPTIONS.map(({ value, label, Icon }) => (
            <DropdownMenuRadioItem key={value} value={value}>
              <Icon aria-hidden="true" className="mr-2 size-4" />
              {label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
