import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Concord — Clinician",
  description: "Clinician dashboard for Concord patient monitoring",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
