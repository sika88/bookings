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
