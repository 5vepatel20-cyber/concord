import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Concord — Understand your medical reports in plain language',
  description:
    'Decode your doctor\'s report instantly. Paste or snap a photo of any medical document and get a plain-language summary, flagged labs, and questions for your care team. No sign-up required.',
  metadataBase: new URL('https://concord.health'),
  icons: { icon: '/favicon.svg' },
  openGraph: {
    title: 'Concord — Decode My Doctor\'s Report',
    description:
      'Paste or snap a photo of any medical document. Get a plain-language summary with flagged labs and questions for your care team. Free, no login needed.',
    type: 'website',
    images: [
      {
        url: '/og.svg',
        width: 1200,
        height: 630,
        alt: 'Concord — Decode My Doctor\'s Report',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Concord — Decode My Doctor\'s Report',
    description:
      'Paste or snap a photo of any medical document. Get a plain-language summary with flagged labs and questions for your care team.',
    images: ['/og.svg'],
  },
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
