import { THEME_STORAGE_KEY } from "@/lib/theme";

// Runs before hydration so a viewer whose stored preference is dark never sees
// a frame of the light palette. It has to be an inline script in <head>: any
// React-driven approach necessarily runs after the first paint.
//
// Kept deliberately small and dependency-free — it is inlined into every
// document, and it must not throw when localStorage is unavailable (private
// windows, blocked site data).
const script = `(function(){try{var t=localStorage.getItem(${JSON.stringify(THEME_STORAGE_KEY)});var d=t==="dark"||(t!=="light"&&window.matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.classList.toggle("dark",d);}catch(e){}})();`;

export function ThemeScript() {
  return <script dangerouslySetInnerHTML={{ __html: script }} />;
}
