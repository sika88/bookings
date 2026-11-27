import Link from "next/link";
import { and, asc, count, eq, gt, gte, inArray } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { Check } from "@/components/icons";
import { publicUrl, requireTenant } from "@/lib/context";
import { expireHolds } from "@/lib/bookings";
import { num } from "@/lib/css";
import BookingCard from "./booking-card";
import PageHead from "./page-head";

export default async function Overview() {
  const { tenant } = await requireTenant();
  await expireHolds(tenant.id);
  const now = new Date();

  const [[svc], [stf], [upcoming], [holds], next] = await Promise.all([
    db.select({ n: count() }).from(services).where(and(eq(services.tenantId, tenant.id), eq(services.active, true))),
    db.select({ n: count() }).from(staff).where(and(eq(staff.tenantId, tenant.id), eq(staff.active, true))),
    db
      .select({ n: count() })
      .from(bookings)
      .where(and(eq(bookings.tenantId, tenant.id), eq(bookings.status, "confirmed"), gte(bookings.startsAt, now))),
    db
      .select({ n: count() })
      .from(bookings)
      .where(and(eq(bookings.tenantId, tenant.id), eq(bookings.status, "pending"), gt(bookings.holdExpiresAt, now))),
    db
      .select({ b: bookings, service: services.name, staffName: staff.displayName, customer: customers.name, phone: customers.phone })
      .from(bookings)
      .innerJoin(services, eq(bookings.serviceId, services.id))
      .innerJoin(staff, eq(bookings.staffId, staff.id))
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .where(and(eq(bookings.tenantId, tenant.id), inArray(bookings.status, ["pending", "confirmed"]), gte(bookings.startsAt, now)))
      .orderBy(asc(bookings.startsAt))
      .limit(5),
  ]);

  const url = await publicUrl(tenant.slug);
  const steps = [
    { done: svc.n > 0, label: "Add at least one service", href: "/services" },
    { done: stf.n > 0, label: "Add a staff member and set their working hours", href: "/staff" },
  ];
  const setupDone = steps.every((s) => s.done);

  const stats = [
    { n: upcoming.n, label: "Upcoming bookings" },
    { n: holds.n, label: "Awaiting deposit" },
    { n: svc.n, label: "Active services" },
    { n: stf.n, label: "Active staff" },
  ];

  return (
    <>
      <PageHead title="Overview" sub="Here is how your bookings are looking." />

      <section className="glass link-card enter" style={num(1)}>
        <div>
          <div className="muted small">Your booking page</div>
          <div className="link-url">{url}</div>
        </div>
        <a href={url} target="_blank" rel="noreferrer" className="act primary">Open page</a>
      </section>

      <div className="stats">
        {stats.map((s, i) => (
          <div key={s.label} className="glass stat enter" style={num(i + 2)}>
            <div className="stat-num">{s.n}</div>
            <div className="stat-label">{s.label}</div>
          </div>
        ))}
      </div>

      {!setupDone && (
        <section className="glass panel enter" style={num(3)}>
          <h2 className="panel-title">Finish setting up</h2>
          <div className="list">
            {steps.map((s) => (
              <div key={s.href} className="todo">
                <span className={`badge${s.done ? " done" : ""}`}>{s.done ? <Check /> : ""}</span>
                {s.done ? (
                  <span className="muted" style={{ textDecoration: "line-through" }}>{s.label}</span>
                ) : (
                  <Link href={s.href} className="link">{s.label}</Link>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="glass panel enter" style={num(4)}>
        <h2 className="panel-title">Next appointments</h2>
        {next.length === 0 ? (
          <p className="muted empty-state">No upcoming appointments yet. They will appear here as customers book.</p>
        ) : (
          <ul className="list">
            {next.map((r) => (
              <BookingCard key={r.b.id} b={r.b} service={r.service} staffName={r.staffName} customer={r.customer} phone={r.phone} tz={tenant.timezone} showDate />
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
