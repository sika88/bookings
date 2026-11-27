import { expireHolds } from "@/lib/bookings";
import { and, eq, gt, inArray, lt } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { addDays } from "date-fns";
import { db } from "@/db";
import { availabilityRules, bookings, services, staff, staffServices, timeOff } from "@/db/schema";

const STEP_MIN = 15;
const MIN_NOTICE_MIN = 60;

export type Slot = { start: string; label: string; staffIds: string[] };

export async function getSlots(opts: {
  tenant: { id: string; timezone: string };
  serviceId: string;
  staffId?: string; // omit for "any available"
  date: string; // YYYY-MM-DD in the tenant's timezone
}): Promise<Slot[]> {
  const { tenant, serviceId, staffId, date } = opts;
  await expireHolds(tenant.id);
  const tz = tenant.timezone;

  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!m) return [];
  const y = Number(m[1]);
  const mo = Number(m[2]) - 1;
  const d = Number(m[3]);

  const dayStart = new TZDate(y, mo, d, 0, 0, 0, 0, tz);
  const dayEnd = addDays(dayStart, 1);
  const weekday = new TZDate(y, mo, d, 12, 0, 0, 0, tz).getDay();

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, serviceId), eq(services.tenantId, tenant.id), eq(services.active, true)))
    .limit(1);
  if (!service) return [];

  const eligible = await db
    .select({ id: staff.id })
    .from(staffServices)
    .innerJoin(staff, eq(staff.id, staffServices.staffId))
    .where(
      and(
        eq(staffServices.serviceId, service.id),
        eq(staff.tenantId, tenant.id),
        eq(staff.active, true),
        staffId ? eq(staff.id, staffId) : undefined,
      ),
    );
  const ids = eligible.map((e) => e.id);
  if (ids.length === 0) return [];

  const [rules, existing, off] = await Promise.all([
    db
      .select()
      .from(availabilityRules)
      .where(
        and(
          eq(availabilityRules.tenantId, tenant.id),
          inArray(availabilityRules.staffId, ids),
          eq(availabilityRules.weekday, weekday),
        ),
      ),
    db
      .select({ staffId: bookings.staffId, startsAt: bookings.startsAt, blocksUntil: bookings.blocksUntil })
      .from(bookings)
      .where(
        and(
          eq(bookings.tenantId, tenant.id),
          inArray(bookings.staffId, ids),
          inArray(bookings.status, ["pending", "confirmed"]),
          lt(bookings.startsAt, dayEnd),
          gt(bookings.blocksUntil, dayStart),
        ),
      ),
    db
      .select({ staffId: timeOff.staffId, startsAt: timeOff.startsAt, endsAt: timeOff.endsAt })
      .from(timeOff)
      .where(
        and(
          eq(timeOff.tenantId, tenant.id),
          inArray(timeOff.staffId, ids),
          lt(timeOff.startsAt, dayEnd),
          gt(timeOff.endsAt, dayStart),
        ),
      ),
  ]);

  const at = (t: string) => {
    const [h, mi] = t.split(":").map(Number);
    return new TZDate(y, mo, d, h, mi, 0, 0, tz).getTime();
  };

  const durMs = service.durationMin * 60_000;
  const bufMs = service.bufferMin * 60_000;
  const earliest = Date.now() + MIN_NOTICE_MIN * 60_000;
  const byStart = new Map<number, Set<string>>();

  for (const id of ids) {
    const busy: Array<[number, number]> = [
      ...existing.filter((b) => b.staffId === id).map((b): [number, number] => [b.startsAt.getTime(), b.blocksUntil.getTime()]),
      ...off.filter((o) => o.staffId === id).map((o): [number, number] => [o.startsAt.getTime(), o.endsAt.getTime()]),
    ];

    for (const r of rules.filter((r) => r.staffId === id)) {
      const wStart = at(r.startTime);
      const wEnd = at(r.endTime);
      for (let s = wStart; s + durMs <= wEnd; s += STEP_MIN * 60_000) {
        if (s < earliest) continue;
        const blockEnd = s + durMs + bufMs;
        if (busy.some(([bs, be]) => s < be && blockEnd > bs)) continue;
        if (!byStart.has(s)) byStart.set(s, new Set());
        byStart.get(s)!.add(id);
      }
    }
  }

  const fmt = new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false });
  return [...byStart.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([ms, set]) => ({
      start: new Date(ms).toISOString(),
      label: fmt.format(new Date(ms)),
      staffIds: [...set],
    }));
}
