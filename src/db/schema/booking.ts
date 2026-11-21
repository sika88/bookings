import {
  boolean, index, integer, pgEnum, pgTable, primaryKey,
  smallint, text, time, timestamp, unique, uuid,
} from "drizzle-orm/pg-core";
import { tenants } from "./tenants";
import { user } from "./auth";

const tstz = (name: string) => timestamp(name, { withTimezone: true });

export const depositType = pgEnum("deposit_type", ["none", "fixed", "percent"]);
export const bookingStatus = pgEnum("booking_status", [
  "pending", "confirmed", "cancelled", "completed", "no_show",
]);

export const staff = pgTable(
  "staff",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    userId: text("user_id").references(() => user.id, { onDelete: "set null" }),
    displayName: text("display_name").notNull(),
    bio: text("bio"),
    active: boolean("active").notNull().default(true),
    createdAt: tstz("created_at").notNull().defaultNow(),
  },
  (t) => [index("staff_tenant_idx").on(t.tenantId)],
);

export const services = pgTable(
  "services",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    description: text("description"),
    durationMin: integer("duration_min").notNull(),
    bufferMin: integer("buffer_min").notNull().default(0),
    pricePesewas: integer("price_pesewas").notNull(),
    // fixed => depositValue is pesewas, percent => depositValue is 1-100
    depositType: depositType("deposit_type").notNull().default("none"),
    depositValue: integer("deposit_value").notNull().default(0),
    active: boolean("active").notNull().default(true),
    createdAt: tstz("created_at").notNull().defaultNow(),
  },
  (t) => [index("services_tenant_idx").on(t.tenantId)],
);

export const staffServices = pgTable(
  "staff_services",
  {
    staffId: uuid("staff_id").notNull().references(() => staff.id, { onDelete: "cascade" }),
    serviceId: uuid("service_id").notNull().references(() => services.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.staffId, t.serviceId] })],
);

// weekday: 0 = Sunday ... 6 = Saturday. Times are local to the tenant's timezone.
// Several rows per day are allowed (e.g. a lunch break splits the day).
export const availabilityRules = pgTable(
  "availability_rules",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    staffId: uuid("staff_id").notNull().references(() => staff.id, { onDelete: "cascade" }),
    weekday: smallint("weekday").notNull(),
    startTime: time("start_time").notNull(),
    endTime: time("end_time").notNull(),
  },
  (t) => [index("availability_staff_idx").on(t.staffId, t.weekday)],
);

export const timeOff = pgTable(
  "time_off",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    staffId: uuid("staff_id").notNull().references(() => staff.id, { onDelete: "cascade" }),
    startsAt: tstz("starts_at").notNull(),
    endsAt: tstz("ends_at").notNull(),
    reason: text("reason"),
  },
  (t) => [index("time_off_staff_idx").on(t.staffId, t.startsAt)],
);

export const customers = pgTable(
  "customers",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    phone: text("phone").notNull(),
    email: text("email"),
    smsOptIn: boolean("sms_opt_in").notNull().default(true),
    createdAt: tstz("created_at").notNull().defaultNow(),
  },
  (t) => [unique("customers_tenant_phone_uq").on(t.tenantId, t.phone)],
);

// startsAt..endsAt is the appointment; blocksUntil = endsAt + service buffer.
// The exclusion constraint (added in a custom migration) uses startsAt..blocksUntil.
export const bookings = pgTable(
  "bookings",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    customerId: uuid("customer_id").notNull().references(() => customers.id),
    serviceId: uuid("service_id").notNull().references(() => services.id),
    staffId: uuid("staff_id").notNull().references(() => staff.id),
    startsAt: tstz("starts_at").notNull(),
    endsAt: tstz("ends_at").notNull(),
    blocksUntil: tstz("blocks_until").notNull(),
    status: bookingStatus("status").notNull().default("pending"),
    holdExpiresAt: tstz("hold_expires_at"),
    totalPesewas: integer("total_pesewas").notNull(),
    depositPesewas: integer("deposit_pesewas").notNull().default(0),
    notes: text("notes"),
    manageToken: text("manage_token")
      .notNull()
      .unique()
      .$defaultFn(() => crypto.randomUUID().replaceAll("-", "")),
    createdAt: tstz("created_at").notNull().defaultNow(),
  },
  (t) => [
    index("bookings_tenant_start_idx").on(t.tenantId, t.startsAt),
    index("bookings_staff_start_idx").on(t.staffId, t.startsAt),
  ],
);
