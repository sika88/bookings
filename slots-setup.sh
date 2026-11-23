#!/usr/bin/env bash
set -e

npm install date-fns @date-fns/tz

cat > src/lib/slots.ts <<'EOF'
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
EOF

cat > "src/app/sites/[tenant]/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { addDays, format } from "date-fns";
import { db } from "@/db";
import { services, staff, staffServices } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";

type SP = { service?: string; staff?: string; date?: string };

const money = (pesewas: number) => `GH₵ ${(pesewas / 100).toFixed(2)}`;

function href(p: SP) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(p)) if (v) q.set(k, v);
  return `?${q.toString()}`;
}

function chip(active: boolean) {
  return `rounded-full border px-4 py-2 text-sm ${active ? "bg-black text-white" : "hover:bg-neutral-100"}`;
}

export default async function TenantHome({
  params,
  searchParams,
}: {
  params: Promise<{ tenant: string }>;
  searchParams: Promise<SP>;
}) {
  const { tenant: slug } = await params;
  const sp = await searchParams;
  const tenant = await getTenantBySlug(slug);
  if (!tenant) notFound();

  const allServices = await db
    .select()
    .from(services)
    .where(and(eq(services.tenantId, tenant.id), eq(services.active, true)))
    .orderBy(asc(services.name));

  const service = allServices.find((s) => s.id === sp.service);

  let people: { id: string; displayName: string }[] = [];
  if (service) {
    people = await db
      .select({ id: staff.id, displayName: staff.displayName })
      .from(staffServices)
      .innerJoin(staff, eq(staff.id, staffServices.staffId))
      .where(and(eq(staffServices.serviceId, service.id), eq(staff.active, true), eq(staff.tenantId, tenant.id)))
      .orderBy(asc(staff.displayName));
  }
  const chosenStaff = people.find((p) => p.id === sp.staff);

  const today = TZDate.tz(tenant.timezone);
  const days = Array.from({ length: 14 }, (_, i) => {
    const day = addDays(today, i);
    return { value: format(day, "yyyy-MM-dd"), label: format(day, "EEE d MMM") };
  });
  const date = days.find((d) => d.value === sp.date)?.value ?? days[0].value;

  const slots = service
    ? await getSlots({ tenant, serviceId: service.id, staffId: chosenStaff?.id, date })
    : [];

  const depositText = (s: (typeof allServices)[number]) =>
    s.depositType === "fixed"
      ? ` · ${money(s.depositValue)} deposit`
      : s.depositType === "percent"
        ? ` · ${s.depositValue}% deposit`
        : "";

  return (
    <main className="mx-auto max-w-2xl space-y-8 p-6 sm:p-8">
      <header>
        <h1 className="text-3xl font-semibold">{tenant.name}</h1>
        <p className="text-neutral-500">Book an appointment</p>
      </header>

      <section>
        <h2 className="mb-3 font-medium">1. Choose a service</h2>
        {allServices.length === 0 && <p className="text-sm text-neutral-500">No services available yet.</p>}
        <ul className="space-y-2">
          {allServices.map((s) => (
            <li key={s.id}>
              <Link
                href={href({ service: s.id })}
                className={`block rounded border p-4 ${service?.id === s.id ? "border-black ring-1 ring-black" : "hover:bg-neutral-50"}`}
              >
                <div className="font-medium">{s.name}</div>
                <div className="text-sm text-neutral-500">
                  {s.durationMin} min · {money(s.pricePesewas)}
                  {depositText(s)}
                </div>
              </Link>
            </li>
          ))}
        </ul>
      </section>

      {service && (
        <section>
          <h2 className="mb-3 font-medium">2. Choose who</h2>
          <div className="flex flex-wrap gap-2">
            <Link href={href({ service: service.id, date })} className={chip(!chosenStaff)}>
              Any available
            </Link>
            {people.map((p) => (
              <Link key={p.id} href={href({ service: service.id, staff: p.id, date })} className={chip(chosenStaff?.id === p.id)}>
                {p.displayName}
              </Link>
            ))}
          </div>
        </section>
      )}

      {service && (
        <section>
          <h2 className="mb-3 font-medium">3. Choose a day</h2>
          <div className="flex flex-wrap gap-2">
            {days.map((d) => (
              <Link
                key={d.value}
                href={href({ service: service.id, staff: chosenStaff?.id, date: d.value })}
                className={chip(d.value === date)}
              >
                {d.label}
              </Link>
            ))}
          </div>
        </section>
      )}

      {service && (
        <section>
          <h2 className="mb-3 font-medium">4. Available times</h2>
          {slots.length === 0 ? (
            <p className="text-sm text-neutral-500">No times available on this day. Try another day.</p>
          ) : (
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
              {slots.map((s) => (
                <span key={s.start} className="rounded border px-3 py-2 text-center text-sm">
                  {s.label}
                </span>
              ))}
            </div>
          )}
          <p className="mt-4 text-xs text-neutral-400">Tapping a time to book comes in the next step.</p>
        </section>
      )}
    </main>
  );
}
EOF

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
