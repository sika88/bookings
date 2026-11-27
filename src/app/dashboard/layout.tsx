import { Bricolage_Grotesque, Instrument_Sans } from "next/font/google";
import "@/styles/glass.css";
import "@/styles/dash.css";

const display = Bricolage_Grotesque({ subsets: ["latin"], variable: "--font-display", display: "swap" });
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body", display: "swap" });

export const metadata = { title: "Dashboard" };

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <div className={`${display.variable} ${body.variable} glass-root`}>{children}</div>;
}
