import { index, integer, jsonb, pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";
import { bookings } from "./booking";

export const paymentStatus = pgEnum("payment_status", ["pending", "success", "failed", "refund_due", "mismatch"]);

export const payments = pgTable(
  "payments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    bookingId: uuid("booking_id").notNull().references(() => bookings.id),
    reference: text("reference").notNull().unique(),
    amountPesewas: integer("amount_pesewas").notNull(),
    currency: text("currency").notNull().default("GHS"),
    network: text("network").notNull(),
    phone: text("phone").notNull(),
    status: paymentStatus("status").notNull().default("pending"),
    providerStatus: text("provider_status"),
    message: text("message"),
    raw: jsonb("raw"),
    lastCheckedAt: timestamp("last_checked_at", { withTimezone: true }),
    paidAt: timestamp("paid_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("payments_booking_idx").on(t.bookingId), index("payments_tenant_status_idx").on(t.tenantId, t.status)],
);
