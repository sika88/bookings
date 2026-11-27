import { index, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";

// Every address a business has used before. Kept so old links redirect and nobody else can take them.
export const tenantSlugHistory = pgTable(
  "tenant_slug_history",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    slug: text("slug").notNull().unique(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("slug_history_tenant_idx").on(t.tenantId)],
);
