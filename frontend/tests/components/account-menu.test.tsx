import { afterEach, describe, expect, it } from "vitest";
import { render, screen, act, cleanup } from "@testing-library/react";

import { AccountMenu } from "@/components/account-menu";
import type { Account } from "@/lib/account";

const base = {
  id: "0198c0de-0000-7000-8000-000000000000",
  plan: "free",
  created_at: "2026-01-01T00:00:00Z",
} as const;

const creator: Account = { ...base, email: "you@acme.example", role: "creator" };
const admin: Account = { ...base, email: "ops@acme.example", role: "admin" };

async function openMenu() {
  const trigger = screen.getByRole("button", { name: "Account menu" });

  await act(async () => {
    trigger.click();
  });
}

describe("AccountMenu", () => {
  afterEach(cleanup);

  it("opens without throwing when the account email is clicked", async () => {
    render(<AccountMenu account={creator} />);

    await expect(openMenu()).resolves.not.toThrow();

    expect(await screen.findByRole("menuitem", { name: "Sign out" })).toBeInTheDocument();
  });

  it("renders no admin affordance for a creator (FR-003)", async () => {
    render(<AccountMenu account={creator} />);
    await openMenu();

    await screen.findByRole("menuitem", { name: "Sign out" });

    expect(screen.queryByRole("menuitem", { name: "Admin" })).not.toBeInTheDocument();
  });

  it("gives an admin account an Admin item above Sign out", async () => {
    render(<AccountMenu account={admin} />);
    await openMenu();

    const items = await screen.findAllByRole("menuitem");

    expect(items.map((item) => item.textContent)).toEqual(["Admin", "Sign out"]);
  });
});
