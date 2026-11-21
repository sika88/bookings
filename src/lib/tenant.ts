import { cache } from "react";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { tenants } from "@/db/schema";

export const getTenantBySlug = cache(async (slug: string) => {
  const [tenant] = await db.select().from(tenants).where(eq(tenants.slug, slug)).limit(1);
  return tenant && tenant.status === "active" ? tenant : null;
});
