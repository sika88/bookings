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
