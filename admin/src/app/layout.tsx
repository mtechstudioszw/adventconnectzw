import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Advent Connect ZW — Admin",
  description: "Operations panel for Advent Connect ZW",
  robots: { index: false, follow: false },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
