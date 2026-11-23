import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { availabilityRules, services, staff, staffServices } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import ActionForm from "@/components/action-form";
import { saveHours, updateStaff } from "../actions";
import { DAYS } from "../days";

const box = "mt-1 w-full rounded border p-2";

export default async function StaffDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { tenant } = await requireTenant();
  if (!isUuid(id)) notFound();

  const [member] = await db
    .select()
    .from(staff)
    .where(and(eq(staff.id, id), eq(staff.tenantId, tenant.id)))
    .limit(1);
  if (!member) notFound();

  const [allServices, linked, rules] = await Promise.all([
    db.select().from(services).where(eq(services.tenantId, tenant.id)).orderBy(asc(services.name)),
    db.select({ serviceId: staffServices.serviceId }).from(staffServices).where(eq(staffServices.staffId, member.id)),
    db
      .select()
      .from(availabilityRules)
      .where(and(eq(availabilityRules.staffId, member.id), eq(availabilityRules.tenantId, tenant.id))),
  ]);

  const linkedIds = new Set(linked.map((l) => l.serviceId));

  const byDay = new Map<number, { s: string; e: string }[]>();
  for (const r of [...rules].sort((a, b) => a.startTime.localeCompare(b.startTime))) {
    const list = byDay.get(r.weekday) ?? [];
    list.push({ s: r.startTime.slice(0, 5), e: r.endTime.slice(0, 5) });
    byDay.set(r.weekday, list);
  }

  return (
    <div className="space-y-10">
      <div>
        <Link href="/staff" className="text-sm underline">← Back to staff</Link>
        <h1 className="mt-3 text-2xl font-semibold">{member.displayName}</h1>
      </div>

      <section>
        <h2 className="mb-3 text-lg font-medium">Profile and services</h2>
        <ActionForm action={updateStaff} submitLabel="Save profile">
          <input type="hidden" name="id" value={member.id} />
          <label className="block text-sm">
            Name
            <input name="displayName" required defaultValue={member.displayName} className={box} />
          </label>
          <label className="block text-sm">
            Short bio (optional)
            <input name="bio" defaultValue={member.bio ?? ""} className={box} />
          </label>

          <fieldset className="space-y-2">
            <legend className="text-sm">Services this person offers</legend>
            {allServices.length === 0 && (
              <p className="text-sm text-neutral-500">
                No services yet. <Link href="/services" className="underline">Add a service</Link> first.
              </p>
            )}
            {allServices.map((s) => (
              <label key={s.id} className="flex items-center gap-2 text-sm">
                <input type="checkbox" name="serviceId" value={s.id} defaultChecked={linkedIds.has(s.id)} />
                {s.name}
                {!s.active && <span className="text-xs text-neutral-500">(hidden)</span>}
              </label>
            ))}
          </fieldset>

          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="active" defaultChecked={member.active} />
            Show on the booking page
          </label>
          <p className="text-xs text-neutral-500">Unticking hides this person from new bookings. Existing bookings are kept.</p>
        </ActionForm>
      </section>

      <section>
        <h2 className="mb-1 text-lg font-medium">Working hours</h2>
        <p className="mb-3 text-sm text-neutral-500">
          Leave a day empty for a day off. Use the second range for a break, for example 09:00 to 13:00, then 14:00 to 18:00.
        </p>
        <ActionForm action={saveHours} submitLabel="Save hours">
          <input type="hidden" name="id" value={member.id} />
          <div>
            {DAYS.map(({ weekday, label }) => {
              const ranges = byDay.get(weekday) ?? [];
              return (
                <div key={weekday} className="grid grid-cols-1 items-center gap-2 border-b py-2 sm:grid-cols-[7rem_1fr_1fr]">
                  <span className="text-sm font-medium">{label}</span>
                  {[1, 2].map((n) => (
                    <div key={n} className="flex items-center gap-1">
                      <input type="time" name={`d${weekday}_s${n}`} defaultValue={ranges[n - 1]?.s ?? ""} className="rounded border p-1 text-sm" />
                      <span className="text-neutral-400">to</span>
                      <input type="time" name={`d${weekday}_e${n}`} defaultValue={ranges[n - 1]?.e ?? ""} className="rounded border p-1 text-sm" />
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        </ActionForm>
      </section>
    </div>
  );
}
