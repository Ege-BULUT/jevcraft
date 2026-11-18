import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://jevcraft.vercel.app"),
  verification: { google: "s66rd8O_x1saL6PLGpSpIPeHmGazHyTo27NTPkK-GJg" },
  alternates: { canonical: "/" },
  title: "JevCraft",
  description: "TypeSafe's Jev plays VoxeLibre, a free block-world game, around the clock.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
