import { cache } from "react";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { getSession } from "./session";

// Resolves the signed-in user's business on the server. Never trust a tenant id from the client.
export const requireTenant = cache(async () => {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await db
    .select({ tenant: tenants, role: memberships.role })
    .from(memberships)
    .innerJoin(tenants, eq(memberships.tenantId, tenants.id))
    .where(eq(memberships.userId, session.user.id))
    .orderBy(asc(memberships.createdAt));

  if (rows.length === 0) redirect("/onboarding");
  return { session, tenant: rows[0].tenant, role: rows[0].role };
});

export const canManage = (role: string) => role === "owner" || role === "admin";

// Subdomain link when the current host sits under the root domain, otherwise a /b/<slug> path on this host.
export async function publicUrl(slug: string) {
  const h = await headers();
  const host = h.get("host") ?? "";
  const hostname = host.split(":")[0];
  const rootFull = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
  const root = rootFull.split(":")[0];
  const proto = h.get("x-forwarded-proto") ?? (hostname === "localhost" || hostname.endsWith(".localhost") ? "http" : "https");

  if (root && (hostname === root || hostname.endsWith(`.${root}`))) return `${proto}://${slug}.${rootFull}`;
  return `${proto}://${host}/b/${slug}`;
}
