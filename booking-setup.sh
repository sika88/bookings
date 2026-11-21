#!/usr/bin/env bash
set -e

# ---------- schema ----------
cat > src/db/schema/booking.ts <<'EOF'
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
EOF

cat > src/db/schema/index.ts <<'EOF'
export * from "./tenants";
export * from "./auth";
export * from "./memberships";
export * from "./booking";
EOF

# ---------- demo seed ----------
cat > src/db/seed-demo.ts <<'EOF'
import { eq } from "drizzle-orm";
import { db } from "./index";
import { availabilityRules, services, staff, staffServices, tenants } from "./schema";

async function main() {
  const slug = process.argv[2];
  if (!slug) {
    console.error("Usage: npm run db:seed:demo -- <tenant-slug>");
    process.exit(1);
  }
  const [tenant] = await db.select().from(tenants).where(eq(tenants.slug, slug)).limit(1);
  if (!tenant) {
    console.error(`No tenant with slug "${slug}"`);
    process.exit(1);
  }
  const existing = await db.select({ id: services.id }).from(services).where(eq(services.tenantId, tenant.id)).limit(1);
  if (existing.length) {
    console.log("This tenant already has services, skipping.");
    return;
  }

  const tenantId = tenant.id;
  const svc = await db
    .insert(services)
    .values([
      { tenantId, name: "Haircut", durationMin: 45, bufferMin: 10, pricePesewas: 5000, depositType: "fixed", depositValue: 1000 },
      { tenantId, name: "Braiding", durationMin: 180, bufferMin: 15, pricePesewas: 25000, depositType: "percent", depositValue: 30 },
      { tenantId, name: "Beard trim", durationMin: 20, bufferMin: 5, pricePesewas: 2000, depositType: "none", depositValue: 0 },
    ])
    .returning();

  const people = await db
    .insert(staff)
    .values([
      { tenantId, displayName: "Ama" },
      { tenantId, displayName: "Kojo" },
    ])
    .returning();

  await db.insert(staffServices).values(
    people.flatMap((p) => svc.map((s) => ({ staffId: p.id, serviceId: s.id }))),
  );

  await db.insert(availabilityRules).values(
    people.flatMap((p) =>
      [1, 2, 3, 4, 5, 6].map((weekday) => ({
        tenantId, staffId: p.id, weekday, startTime: "09:00", endTime: "18:00",
      })),
    ),
  );

  console.log(`Seeded ${svc.length} services, ${people.length} staff, Mon-Sat 09:00-18:00 for "${slug}".`);
}
main().catch((e) => { console.error(e); process.exit(1); });
EOF

# ---------- overlap test ----------
cat > src/db/test-overlap.ts <<'EOF'
import { eq, inArray } from "drizzle-orm";
import { db } from "./index";
import { bookings, customers, services, staff, tenants } from "./schema";

const code = (e: any) => e?.code ?? e?.cause?.code;

async function main() {
  const slug = process.argv[2] ?? "";
  const [tenant] = await db.select().from(tenants).where(eq(tenants.slug, slug)).limit(1);
  if (!tenant) throw new Error("Usage: npm run db:test:overlap -- <tenant-slug>");
  const [svc] = await db.select().from(services).where(eq(services.tenantId, tenant.id)).limit(1);
  const [person] = await db.select().from(staff).where(eq(staff.tenantId, tenant.id)).limit(1);
  if (!svc || !person) throw new Error("Run db:seed:demo first");

  const [cust] = await db
    .insert(customers)
    .values({ tenantId: tenant.id, name: "Overlap Test", phone: `test-${Date.now()}` })
    .returning();

  const base = new Date(Date.now() + 7 * 24 * 3600 * 1000);
  base.setUTCHours(10, 0, 0, 0);
  const at = (min: number) => new Date(base.getTime() + min * 60000);
  const mk = (start: number, end: number, block: number) => ({
    tenantId: tenant.id,
    customerId: cust.id,
    serviceId: svc.id,
    staffId: person.id,
    startsAt: at(start),
    endsAt: at(end),
    blocksUntil: at(block),
    status: "confirmed" as const,
    totalPesewas: 0,
    depositPesewas: 0,
  });

  const ids: string[] = [];
  try {
    // 10:00-10:45, blocked until 10:55 (10 min buffer)
    const [a] = await db.insert(bookings).values(mk(0, 45, 55)).returning({ id: bookings.id });
    ids.push(a.id);
    console.log("1. first booking 10:00-10:45 (+10 min buffer): created");

    try {
      const [b] = await db.insert(bookings).values(mk(30, 75, 85)).returning({ id: bookings.id });
      ids.push(b.id);
      console.log("2. overlapping booking 10:30: ALLOWED  <-- constraint is missing!");
    } catch (e) {
      console.log(
        code(e) === "23P01"
          ? "2. overlapping booking 10:30: rejected by database (correct)"
          : `2. rejected for a different reason (code ${code(e)}): ${(e as Error).message}`,
      );
    }

    // starts exactly when the buffer ends
    const [c] = await db.insert(bookings).values(mk(55, 100, 110)).returning({ id: bookings.id });
    ids.push(c.id);
    console.log("3. back-to-back booking at 10:55: allowed (correct)");
  } finally {
    if (ids.length) await db.delete(bookings).where(inArray(bookings.id, ids));
    await db.delete(customers).where(eq(customers.id, cust.id));
    console.log("cleaned up test rows");
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
EOF

npm pkg set scripts.db:seed:demo="tsx --env-file=.env.local src/db/seed-demo.ts"
npm pkg set scripts.db:test:overlap="tsx --env-file=.env.local src/db/test-overlap.ts"

# ---------- migrations ----------
npm run db:generate

if ! ls drizzle/*booking_no_overlap.sql >/dev/null 2>&1; then
  npx drizzle-kit generate --custom --name=booking_no_overlap
  F=$(ls drizzle/*booking_no_overlap.sql | tail -1)
  cat >> "$F" <<'SQL'
CREATE EXTENSION IF NOT EXISTS btree_gist;
--> statement-breakpoint
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_time_valid" CHECK ("ends_at" > "starts_at" AND "blocks_until" >= "ends_at");
--> statement-breakpoint
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_no_overlap" EXCLUDE USING gist ("staff_id" WITH =, tstzrange("starts_at", "blocks_until") WITH &&) WHERE ("status" IN ('pending', 'confirmed'));
SQL
fi

npm run db:migrate

echo ""
echo "Done. Now seed demo data and run the test (use YOUR tenant slug):"
echo "  npm run db:seed:demo -- your-slug"
echo "  npm run db:test:overlap -- your-slug"
