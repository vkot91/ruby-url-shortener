import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

export default defineConfig({
  plugins: [react()],
  test: {
    // Phase 1 ships green empty suites; component tests arrive with the
    // components in Phase 4.
    passWithNoTests: true,
    environment: "jsdom",
    globals: true,
    setupFiles: ["./tests/setup.ts"],
    // Playwright owns tests/e2e; without this exclusion Vitest tries to collect
    // them and fails on the Playwright-only globals.
    include: ["tests/**/*.test.{ts,tsx}"],
    exclude: ["tests/e2e/**"],
  },
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
});
