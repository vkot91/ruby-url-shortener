export const THEME_STORAGE_KEY = "snip-theme";

export type Theme = "system" | "light" | "dark";

export function isTheme(value: unknown): value is Theme {
  return value === "system" || value === "light" || value === "dark";
}

/**
 * Reads the stored preference. Returns "system" when nothing is stored, when
 * the stored value is unrecognised, or when storage itself throws — every one
 * of those means "the viewer has expressed no preference".
 */
export function readStoredTheme(): Theme {
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);

    return isTheme(stored) ? stored : "system";
  } catch {
    return "system";
  }
}

/**
 * Applies a theme to the document and persists it. "system" removes the stored
 * value rather than writing the word, so a viewer who returns to system
 * follows their OS if it changes later.
 */
export function applyTheme(theme: Theme): void {
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const isDark = theme === "dark" || (theme === "system" && prefersDark);

  document.documentElement.classList.toggle("dark", isDark);

  try {
    if (theme === "system") {
      window.localStorage.removeItem(THEME_STORAGE_KEY);
    } else {
      window.localStorage.setItem(THEME_STORAGE_KEY, theme);
    }
  } catch {
    // Storage is unavailable. The class is already applied, so the current
    // page is correct; only persistence across navigations is lost.
  }
}
