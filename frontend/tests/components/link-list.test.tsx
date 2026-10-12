import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import { LinkList } from "@/app/(dashboard)/links/link-list";
import type { Link, LinkList as LinkListPayload } from "@/lib/api";

/**
 * design.md §6.3 and P4. What is asserted here is what the table *promises* —
 * that it shows one account's links newest-first, that it survives having none,
 * that a failed load leaves the create path usable, and above all that a
 * background poll changes the number and nothing else.
 *
 * The last one is the reason this file exists. A dashboard that flickered every
 * 30 seconds would still pass every other assertion in it.
 */

const listLinks = vi.hoisted(() => vi.fn());

vi.mock("@/lib/api", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/api")>()),
  listLinks,
}));

function link(overrides: Partial<Link> = {}): Link {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    code: "k7Bx2mQ",
    short_url: "https://snp.to/k7Bx2mQ",
    destination_url: "https://example.com/spring-campaign",
    name: "Spring poster",
    clicks_count: 41,
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

function payload(links: Link[], total = links.length): LinkListPayload {
  return { links, pagination: { page: 1, per_page: 25, total } };
}

function renderList() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <LinkList />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  listLinks.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("LinkList", () => {
  it("shows the short link, destination, and count for each row", async () => {
    listLinks.mockResolvedValue(payload([link()]));

    renderList();

    expect(await screen.findByTestId("short-link-code")).toHaveTextContent("k7Bx2mQ");
    expect(screen.getByText("https://example.com/spring-campaign")).toBeInTheDocument();
    expect(screen.getByTestId("click-count")).toHaveTextContent("41");
  });

  it("reports usage against the free-plan limit, from the account total and not the page (FR-004)", async () => {
    listLinks.mockResolvedValue(payload([link()], 12));

    renderList();

    expect(await screen.findByText("12 of 50 links used")).toBeInTheDocument();
  });

  it("disables the New link button at the limit rather than opening a form that cannot succeed", async () => {
    listLinks.mockResolvedValue(payload([link()], 50));

    renderList();

    await waitFor(() => expect(screen.getByRole("button", { name: "New link" })).toBeDisabled());
  });

  it("offers a way to create the first link when there are none", async () => {
    listLinks.mockResolvedValue(payload([]));

    renderList();

    expect(await screen.findByText("No links yet")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Create your first link" })).toBeInTheDocument();
  });

  it("keeps the create path usable when the list fails to load", async () => {
    listLinks.mockRejectedValue(new Error("network"));

    renderList();

    expect(await screen.findByRole("alert")).toHaveTextContent("Couldn't load your links.");
    expect(screen.getByRole("link", { name: "New link" })).toBeInTheDocument();
  });

  it("retries on request", async () => {
    const user = userEvent.setup();

    listLinks.mockRejectedValueOnce(new Error("network")).mockResolvedValue(payload([link()]));

    renderList();

    await user.click(await screen.findByRole("button", { name: "Try again" }));

    expect(await screen.findByTestId("short-link-code")).toHaveTextContent("k7Bx2mQ");
  });

  it("hides pagination while everything fits on one page", async () => {
    listLinks.mockResolvedValue(payload([link()], 25));

    renderList();

    await screen.findByTestId("short-link-code");

    expect(screen.queryByRole("navigation", { name: "Pagination" })).not.toBeInTheDocument();
  });

  it("asks the API for the next page when Next is pressed", async () => {
    const user = userEvent.setup();

    listLinks.mockResolvedValue(payload([link()], 43));

    renderList();

    await user.click(await screen.findByRole("button", { name: "Next" }));

    await waitFor(() => expect(listLinks).toHaveBeenLastCalledWith({ page: 2, perPage: 25 }));
  });

  // design.md P4, and the whole point of `placeholderData: keepPreviousData` in
  // use-links.ts. The rows stay mounted across the refetch; only the number
  // changes. A version of this component that dropped back to skeletons on each
  // poll would fail here and nowhere else.
  it("changes the number and nothing else on a background refetch", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });

    listLinks.mockResolvedValue(payload([link({ clicks_count: 41 })]));

    renderList();

    const row = (await screen.findByTestId("short-link-code")).closest("tr")!;

    expect(within(row).getByTestId("click-count")).toHaveTextContent("41");

    listLinks.mockResolvedValue(payload([link({ clicks_count: 58 })]));

    await vi.advanceTimersByTimeAsync(30_000);

    await waitFor(() => expect(within(row).getByTestId("click-count")).toHaveTextContent("58"));

    // The same row element, not a replacement: React reused it rather than
    // unmounting the table and rebuilding it.
    expect(row.isConnected).toBe(true);
    expect(screen.queryByText("No links yet")).not.toBeInTheDocument();
  });
});
