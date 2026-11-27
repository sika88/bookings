import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { availabilityRules, services, staff, staffServices } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { Chevron } from "@/components/icons";
import { requireTenant } from "@/lib/context";
import { hueVar, num } from "@/lib/css";
import { hueOf } from "@/lib/hue";
import { isUuid } from "@/lib/ids";
import { saveHours, updateStaff } from "../actions";
import { DAYS } from "../days";

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
    <>
      <Link href="/staff" className="back enter" style={num(0)}>
        <Chevron /> Back to staff
      </Link>

      <header className="item-lead enter" style={num(1)}>
        <span className="avatar" style={{ ...hueVar(hueOf(member.displayName)), width: "3.2rem", height: "3.2rem", fontSize: "1.3rem" }}>
          {member.displayName.charAt(0).toUpperCase()}
        </span>
        <h1 className="display h-md" style={{ marginBottom: 0 }}>{member.displayName}</h1>
      </header>

      <section className="glass panel enter" style={{ ...num(2), maxWidth: "44rem" }}>
        <h2 className="panel-title">Profile and services</h2>
        <ActionForm action={updateStaff} submitLabel="Save profile">
          <input type="hidden" name="id" value={member.id} />
          <label>
            Name
            <input name="displayName" required defaultValue={member.displayName} className="field" />
          </label>
          <label>
            Short bio (optional)
            <input name="bio" defaultValue={member.bio ?? ""} className="field" />
          </label>

          <fieldset className="fieldset">
            <legend>Services this person offers</legend>
            {allServices.length === 0 ? (
              <p className="muted small">
                No services yet. <Link href="/services" className="link">Add a service</Link> first.
              </p>
            ) : (
              <div className="chips">
                {allServices.map((s) => (
                  <label key={s.id} className="chip">
                    <input type="checkbox" name="serviceId" value={s.id} defaultChecked={linkedIds.has(s.id)} />
                    <span>{s.name}</span>
                    {!s.active && <small className="muted">hidden</small>}
                  </label>
                ))}
              </div>
            )}
          </fieldset>

          <label className="switch">
            <input type="checkbox" name="active" defaultChecked={member.active} />
            <span className="track" aria-hidden="true" />
            Show on the booking page
          </label>
          <p className="muted small">Turning this off hides this person from new bookings. Existing bookings are kept.</p>
        </ActionForm>
      </section>

      <section className="glass panel enter" style={{ ...num(3), maxWidth: "44rem" }}>
        <h2 className="panel-title">Working hours</h2>
        <p className="muted small" style={{ marginTop: "-0.5rem", marginBottom: "0.75rem" }}>
          Leave a day empty for a day off. Use the second range for a break, for example 09:00 to 13:00, then 14:00 to 18:00.
        </p>
        <ActionForm action={saveHours} submitLabel="Save hours">
          <input type="hidden" name="id" value={member.id} />
          <div className="hours">
            {DAYS.map(({ weekday, label }) => {
              const ranges = byDay.get(weekday) ?? [];
              return (
                <div key={weekday} className="hours-row">
                  <span className="day-label">{label}</span>
                  {[1, 2].map((n) => (
                    <div key={n} className="range">
                      <input type="time" name={`d${weekday}_s${n}`} defaultValue={ranges[n - 1]?.s ?? ""} className="field" aria-label={`${label} range ${n} start`} />
                      <span className="to">to</span>
                      <input type="time" name={`d${weekday}_e${n}`} defaultValue={ranges[n - 1]?.e ?? ""} className="field" aria-label={`${label} range ${n} end`} />
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        </ActionForm>
      </section>
    </>
  );
}
