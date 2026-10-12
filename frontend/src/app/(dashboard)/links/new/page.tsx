import type { Metadata } from "next";

import { CreateLink } from "@/app/(dashboard)/links/new/create-link";

export const metadata: Metadata = { title: "New link · Snip" };

export default function NewLinkPage() {
  return <CreateLink />;
}
