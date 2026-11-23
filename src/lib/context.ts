import { cache } from "react";
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

export function publicUrl(slug: string) {
  const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN!;
  const proto = process.env.NODE_ENV === "production" ? "https" : "http";
  return `${proto}://${slug}.${root}`;
}
