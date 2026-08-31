import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, act } from "@testing-library/react";

import { CopyButton } from "@/components/copy-button";

function mockClipboard() {
  const writeText = vi.fn().mockResolvedValue(undefined);

  Object.assign(navigator, { clipboard: { writeText } });

  return writeText;
}

describe("CopyButton", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  async function click(element: HTMLElement) {
    await act(async () => {
      element.click();
    });
  }

  it("writes the value to the clipboard", async () => {
    const writeText = mockClipboard();

    render(<CopyButton value="snp.to/k7Bx2mQ" label="Copy short link" />);
    await click(screen.getByRole("button"));

    expect(writeText).toHaveBeenCalledWith("snp.to/k7Bx2mQ");
  });

  it("swaps to a success state in place rather than rendering a toast", async () => {
    mockClipboard();

    render(<CopyButton value="snp.to/k7Bx2mQ" label="Copy short link" />);
    const button = screen.getByRole("button");

    expect(button).toHaveAccessibleName("Copy short link");

    await click(button);

    expect(screen.getAllByRole("button")).toHaveLength(1);
    expect(screen.getByRole("button")).toHaveAccessibleName("Copied");
  });

  it("holds the success state for two seconds, then reverts", async () => {
    mockClipboard();

    render(<CopyButton value="snp.to/k7Bx2mQ" label="Copy short link" />);
    await click(screen.getByRole("button"));

    await act(async () => {
      vi.advanceTimersByTime(1_900);
    });

    expect(screen.getByRole("button")).toHaveAccessibleName("Copied");

    await act(async () => {
      vi.advanceTimersByTime(200);
    });

    expect(screen.getByRole("button")).toHaveAccessibleName("Copy short link");
  });

  it("announces the confirmation politely", async () => {
    mockClipboard();

    const { container } = render(<CopyButton value="snp.to/k7Bx2mQ" label="Copy short link" />);
    const live = container.querySelector('[aria-live="polite"]');

    expect(live).not.toBeNull();
    expect(live).toHaveTextContent("");

    await click(screen.getByRole("button"));

    expect(container.querySelector('[aria-live="polite"]')).toHaveTextContent("Copied");
  });

  it("restarts the two seconds when clicked again mid-confirmation", async () => {
    mockClipboard();

    render(<CopyButton value="snp.to/k7Bx2mQ" label="Copy short link" />);
    const button = screen.getByRole("button");

    await click(button);

    await act(async () => {
      vi.advanceTimersByTime(1_500);
    });

    await click(screen.getByRole("button"));

    await act(async () => {
      vi.advanceTimersByTime(1_500);
    });

    expect(screen.getByRole("button")).toHaveAccessibleName("Copied");
  });
});
