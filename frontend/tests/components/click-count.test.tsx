import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

import { ClickCount } from "@/components/click-count";
import { ShortLink } from "@/components/short-link";
import { EmptyState } from "@/components/empty-state";

describe("ClickCount", () => {
  const values = [0, 8, 4051];

  it("renders the count", () => {
    render(<ClickCount value={4051} />);

    expect(screen.getByText("4,051")).toBeInTheDocument();
  });

  it("uses tabular figures at every magnitude", () => {
    for (const value of values) {
      const { unmount } = render(<ClickCount value={value} />);

      expect(screen.getByTestId("click-count")).toHaveClass("tabular-nums");

      unmount();
    }
  });

  it("keeps an identical class list across magnitudes, so width cannot depend on the value", () => {
    const classNames = values.map((value) => {
      const { unmount } = render(<ClickCount value={value} />);
      const className = screen.getByTestId("click-count").className;

      unmount();

      return className;
    });

    expect(new Set(classNames).size).toBe(1);
  });

  it("thousands-separates so the column stays readable", () => {
    render(<ClickCount value={1284} />);

    expect(screen.getByText("1,284")).toBeInTheDocument();
  });
});

describe("ShortLink", () => {
  it("renders the domain and the code as separate elements so the code can lead", () => {
    render(<ShortLink domain="snp.to" code="k7Bx2mQ" />);

    expect(screen.getByTestId("short-link-domain")).toHaveTextContent("snp.to/");
    expect(screen.getByTestId("short-link-code")).toHaveTextContent("k7Bx2mQ");
  });

  it("gives the code the foreground and the domain the muted role", () => {
    render(<ShortLink domain="snp.to" code="k7Bx2mQ" />);

    expect(screen.getByTestId("short-link-code")).toHaveClass("text-foreground");
    expect(screen.getByTestId("short-link-domain")).toHaveClass("text-muted-foreground");
  });

  it("exposes the whole short link as one accessible string", () => {
    render(<ShortLink domain="snp.to" code="k7Bx2mQ" />);

    expect(screen.getByTestId("short-link")).toHaveTextContent("snp.to/k7Bx2mQ");
  });
});

describe("EmptyState", () => {
  it("renders a heading and a supporting line", () => {
    render(<EmptyState heading="No links yet" description="Your first one takes a minute." />);

    expect(screen.getByRole("heading", { name: "No links yet" })).toBeInTheDocument();
    expect(screen.getByText("Your first one takes a minute.")).toBeInTheDocument();
  });

  it("renders an action only when one is given", () => {
    const { rerender } = render(<EmptyState heading="Nothing in the queue." />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();

    rerender(
      <EmptyState
        heading="No links yet"
        action={<button type="button">Create your first link</button>}
      />,
    );

    expect(screen.getByRole("button", { name: "Create your first link" })).toBeInTheDocument();
  });
});
