"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Calendar, Gear, Grid, List, Users } from "@/components/icons";

const items = [
  { href: "/", label: "Overview", Icon: Grid },
  { href: "/bookings", label: "Bookings", Icon: Calendar },
  { href: "/services", label: "Services", Icon: List },
  { href: "/staff", label: "Staff", Icon: Users },
  { href: "/settings", label: "Settings", Icon: Gear },
];

export default function Nav() {
  const raw = usePathname();
  // the proxy rewrites app.* requests to /dashboard/*, so normalise both forms
  const path = raw.replace(/^\/dashboard(?=\/|$)/, "") || "/";

  return (
    <nav className="nav" aria-label="Dashboard">
      {items.map(({ href, label, Icon }) => {
        const active = href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`);
        return (
          <Link key={href} href={href} aria-current={active ? "page" : undefined} className={`nav-link${active ? " active" : ""}`}>
            <Icon />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
