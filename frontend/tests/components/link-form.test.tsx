import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import { LinkForm } from "@/components/link-form";
import { ApiError, type Link } from "@/lib/api";

/**
 * design.md §6.4 and P5. The create form's job is not to submit — it is to
 * explain a refusal well enough that the next attempt succeeds, and there are
 * six distinct refusals to explain.
 *
 * Each `error.code` is asserted against its own copy, because the failure mode
 * this guards against is not "no message" but "the wrong message": a form that
 * mapped `blocked_domain` to the private-address wording would look entirely
 * healthy and send somebody off to debug their network.
 */

function renderForm(
  onSubmit: (values: { destination_url: string; name?: string }) => Promise<Link>,
) {
  const onCancel = vi.fn();

  render(<LinkForm submitLabel="Create link" onSubmit={onSubmit} onCancel={onCancel} />);

  return { onCancel };
}

async function submitWith(url: string) {
  const user = userEvent.setup();

  await user.clear(screen.getByLabelText("Destination URL"));
  await user.type(screen.getByLabelText("Destination URL"), url);
  await user.click(screen.getByRole("button", { name: "Create link" }));

  return user;
}

function rejectWith(code: string, status = 422) {
  return vi.fn().mockRejectedValue(new ApiError(code, "Rejected", status));
}

describe("LinkForm", () => {
  it("sends the destination and drops an empty optional name", async () => {
    const onSubmit = vi.fn().mockResolvedValue({} as Link);

    renderForm(onSubmit);
    await submitWith("https://example.com/a");

    expect(onSubmit).toHaveBeenCalledWith({
      destination_url: "https://example.com/a",
      name: undefined,
    });
  });

  it("refuses to submit an empty destination, without a round trip", async () => {
    const onSubmit = vi.fn();

    renderForm(onSubmit);

    await userEvent.setup().click(screen.getByRole("button", { name: "Create link" }));

    expect(await screen.findByText("Enter a web address.")).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it.each([
    ["invalid_url", "That doesn't look like a web address. Check for typos."],
    ["unsupported_scheme", "Links must start with http:// or https://."],
    [
      "private_address",
      "That address points inside a private network, so it wouldn't work for your visitors.",
    ],
    ["self_referential", "That's already a Snip link. Share it directly instead."],
    ["blocked_domain", "That destination is on our blocked list and can't be shortened."],
  ])("explains %s beside the destination field", async (code, message) => {
    renderForm(rejectWith(code));
    await submitWith("https://example.com/a");

    expect(await screen.findByText(message)).toBeInTheDocument();
    expect(screen.getByLabelText("Destination URL")).toHaveAttribute("aria-invalid", "true");
  });

  // The sixth code is form-level rather than field-level, and the difference is
  // not cosmetic: no edit to the destination can fix it, so leaving submit
  // enabled would invite an attempt that is guaranteed to fail again.
  it("renders link_limit_reached above the form and disables submit", async () => {
    renderForm(rejectWith("link_limit_reached"));
    await submitWith("https://example.com/a");

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "You've reached the 50-link limit on the free plan.",
    );
    expect(screen.getByRole("button", { name: "Create link" })).toBeDisabled();
  });

  // FR-019, restated where it matters: somebody refused by the hourly limit
  // needs to know their published links still work.
  it("promises that existing redirects are unaffected when the hourly limit is hit", async () => {
    renderForm(rejectWith("rate_limited", 429));
    await submitWith("https://example.com/a");

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "your existing links are unaffected",
    );
  });

  it("falls back to the API's own message for a code it does not know", async () => {
    const onSubmit = vi
      .fn()
      .mockRejectedValue(new ApiError("something_new", "The API said something new", 422));

    renderForm(onSubmit);
    await submitWith("https://example.com/a");

    expect(await screen.findByText("The API said something new")).toBeInTheDocument();
  });
});
