import { eq } from "drizzle-orm";
import { db } from "@/db";
import { tenants, tenantSlugHistory } from "@/db/schema";
import { RESERVED_SLUGS } from "./reserved";

const FORMAT = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// Validates a booking-page address. Pass ownTenantId when an existing business is renaming.
export async function checkSlug(input: string, ownTenantId?: string): Promise<{ error: string } | { slug: string }> {
  const slug = input.trim().toLowerCase();

  if (slug.length < 3) return { error: "Address must be at least 3 characters" };
  if (slug.length > 40) return { error: "Address can be at most 40 characters" };
  if (!FORMAT.test(slug)) return { error: "Use only letters, numbers and single hyphens" };
  if (RESERVED_SLUGS.has(slug)) return { error: "That address is reserved" };

  const [current] = await db.select({ id: tenants.id }).from(tenants).where(eq(tenants.slug, slug)).limit(1);
  if (current) return { error: current.id === ownTenantId ? "That is already your address" : "That address is already taken" };

  // addresses other businesses used before stay reserved for them; your own old ones can be taken back
  const [old] = await db
    .select({ tenantId: tenantSlugHistory.tenantId })
    .from(tenantSlugHistory)
    .where(eq(tenantSlugHistory.slug, slug))
    .limit(1);
  if (old && old.tenantId !== ownTenantId) return { error: "That address is already taken" };

  return { slug };
}
