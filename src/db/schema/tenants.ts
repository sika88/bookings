import { pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

export const tenantType = pgEnum("tenant_type", ["salon", "clinic", "barber", "venue"]);

export const tenants = pgTable("tenants", {
  id: uuid("id").primaryKey().defaultRandom(),
  slug: text("slug").notNull().unique(),
  name: text("name").notNull(),
  type: tenantType("type").notNull(),
  timezone: text("timezone").notNull().default("Africa/Accra"),
  currency: text("currency").notNull().default("GHS"),
  status: text("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
