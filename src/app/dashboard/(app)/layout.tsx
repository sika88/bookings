import Link from "next/link";
import { publicUrl, requireTenant } from "@/lib/context";
import SignOutButton from "../sign-out-button";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { session, tenant } = await requireTenant();

  return (
    <div className="mx-auto max-w-3xl p-4 sm:p-8">
      <header className="mb-8 flex flex-wrap items-center justify-between gap-3 border-b pb-4">
        <div>
          <div className="font-semibold">{tenant.name}</div>
          <div className="text-xs text-neutral-500">{session.user.email}</div>
        </div>
        <nav className="flex flex-wrap items-center gap-4 text-sm">
          <Link href="/">Overview</Link>
          <Link href="/services">Services</Link>
          <Link href="/staff">Staff</Link>
          <a href={publicUrl(tenant.slug)} target="_blank" rel="noreferrer" className="underline">
            View booking page
          </a>
          <SignOutButton />
        </nav>
      </header>
      {children}
    </div>
  );
}
