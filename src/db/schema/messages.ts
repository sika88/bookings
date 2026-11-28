import { index, integer, pgEnum, pgTable, text, timestamp, unique, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";
import { bookings } from "./booking";

export const messageKind = pgEnum("message_kind", ["confirmation", "reminder_24h", "reminder_2h", "cancellation"]);
export const messageStatus = pgEnum("message_status", ["pending", "sent", "failed", "skipped"]);

// Outbox: one row per text we intend to send. Unique per booking + kind, so nothing is sent twice.
export const messages = pgTable(
  "messages",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    bookingId: uuid("booking_id").notNull().references(() => bookings.id),
    kind: messageKind("kind").notNull(),
    status: messageStatus("status").notNull().default("pending"),
    sendAt: timestamp("send_at", { withTimezone: true }).notNull(),
    claimedAt: timestamp("claimed_at", { withTimezone: true }),
    attempts: integer("attempts").notNull().default(0),
    lastError: text("last_error"),
    toPhone: text("to_phone"),
    body: text("body"),
    providerId: text("provider_id"),
    sentAt: timestamp("sent_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    unique("messages_booking_kind_uq").on(t.bookingId, t.kind),
    index("messages_due_idx").on(t.status, t.sendAt),
    index("messages_tenant_idx").on(t.tenantId, t.createdAt),
  ],
);
