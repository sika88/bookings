import type { CSSProperties } from "react";
import Aurora from "@/components/aurora";
import { External } from "@/components/icons";
import { publicUrl, requireTenant } from "@/lib/context";
import { hueOf } from "@/lib/hue";
import SignOutButton from "../sign-out-button";
import Nav from "./nav";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { session, tenant } = await requireTenant();

  return (
    <div className="dash" style={{ "--h": hueOf(tenant.slug) } as CSSProperties}>
      <Aurora />
      <aside className="glass sidebar enter">
        <div className="side-brand">
          <div className="monogram">{tenant.name.charAt(0).toUpperCase()}</div>
          <div className="side-name">{tenant.name}</div>
        </div>
        <Nav />
        <div className="side-foot">
          <a href={publicUrl(tenant.slug)} target="_blank" rel="noreferrer" className="act primary">
            View booking page <External />
          </a>
          <div className="muted small side-email">{session.user.email}</div>
          <SignOutButton />
        </div>
      </aside>
      <div className="main">{children}</div>
    </div>
  );
}
