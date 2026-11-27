import { cache } from "react";
import { headers } from "next/headers";
import { permanentRedirect } from "next/navigation";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { tenants, tenantSlugHistory } from "@/db/schema";

async function renamedUrl(newSlug: string) {
  const h = await headers();
  const host = h.get("host") ?? "";
  const hostname = host.split(":")[0];
  const proto = h.get("x-forwarded-proto") ?? (hostname === "localhost" || hostname.endsWith(".localhost") ? "http" : "https");
  const orig = h.get("x-orig") ?? "/";
  const base = h.get("x-base") ?? "";

  if (/^\/b\/[a-z0-9-]+$/.test(base)) {
    const rest = orig.startsWith(base) ? orig.slice(base.length) : "";
    return `${proto}://${host}/b/${newSlug}${rest || "/"}`;
  }

  const rootFull = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
  return rootFull ? `${proto}://${newSlug}.${rootFull}${orig}` : null;
}

export const getTenantBySlug = cache(async (slug: string) => {
  const [tenant] = await db.select().from(tenants).where(eq(tenants.slug, slug)).limit(1);
  if (tenant) return tenant.status === "active" ? tenant : null;

  const [old] = await db
    .select({ slug: tenants.slug, status: tenants.status })
    .from(tenantSlugHistory)
    .innerJoin(tenants, eq(tenantSlugHistory.tenantId, tenants.id))
    .where(eq(tenantSlugHistory.slug, slug))
    .limit(1);

  if (old && old.status === "active") {
    const url = await renamedUrl(old.slug);
    if (url) permanentRedirect(url);
  }
  return null;
});
