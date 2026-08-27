import type { Metadata } from "next";
import { Figtree, JetBrains_Mono } from "next/font/google";

import { ThemeScript } from "@/components/theme-script";

import "./globals.css";

// design.md §4.1. Figtree carries the UI; JetBrains Mono exists for one
// reason — a 7-character random code (FR-009) gets read and re-typed by
// humans, and it disambiguates 0/O and l/1/I.
const figtree = Figtree({
  variable: "--font-figtree",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  title: "Snip",
  description: "Short links that keep working after you publish them.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <ThemeScript />
      </head>
      <body className={`${figtree.variable} ${jetbrainsMono.variable} antialiased`}>
        {children}
      </body>
    </html>
  );
}
