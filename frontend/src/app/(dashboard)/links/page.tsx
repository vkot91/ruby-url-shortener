import type { Metadata } from "next";

import { LinkList } from "@/app/(dashboard)/links/link-list";

export const metadata: Metadata = { title: "Your links · Snip" };

/**
 * design.md §6.3 — the screen the product is judged on.
 *
 * A server component whose only job is the document title. Everything below it
 * is a client component because the click count is polled (T108), and a table
 * that re-renders every 30 seconds cannot be server-rendered per poll without
 * shipping the whole page down each time.
 */
export default function LinksPage() {
  return <LinkList />;
}
