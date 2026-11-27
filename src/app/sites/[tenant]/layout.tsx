import type { CSSProperties } from "react";
import type { Metadata } from "next";
import { Bricolage_Grotesque, Instrument_Sans } from "next/font/google";
import { getTenantBySlug } from "@/lib/tenant";
import { hueOf } from "@/lib/hue";
import "@/styles/glass.css";

const display = Bricolage_Grotesque({ subsets: ["latin"], variable: "--font-display", display: "swap" });
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body", display: "swap" });

export async function generateMetadata({ params }: { params: Promise<{ tenant: string }> }): Promise<Metadata> {
  const { tenant: slug } = await params;
  const tenant = await getTenantBySlug(slug);
  return { title: tenant ? `Book at ${tenant.name}` : "Not found" };
}

export default async function SiteLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ tenant: string }>;
}) {
  const { tenant: slug } = await params;

  return (
    <div
      className={`${display.variable} ${body.variable} glass-root`}
      style={{ "--h": hueOf(slug) } as CSSProperties}
    >
      <div className="aurora" aria-hidden="true">
        <i /><i /><i />
        <b /><b /><b />
      </div>
      {children}
    </div>
  );
}
