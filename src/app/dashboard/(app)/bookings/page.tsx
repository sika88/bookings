import { and, asc, desc, eq, gte } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, payments, services, staff } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { expireHolds } from "@/lib/bookings";
import { num } from "@/lib/css";
import { formatDay, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import BookingCard from "../booking-card";
import PageHead from "../page-head";
import { setBookingStatus } from "./actions";

function Action({ id, status, label, danger }: { id: string; status: string; label: string; danger?: boolean }) {
  return (
    <form action={setBookingStatus}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="status" value={status} />
      <button className={`act${danger ? " danger" : ""}`}>{label}</button>
    </form>
  );
}

export default async function BookingsPage() {
  const { tenant } = await requireTenant();
  await expireHolds(tenant.id);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);

  const [rows, refunds] = await Promise.all([
    db
      .select({ b: bookings, service: services.name, staffName: staff.displayName, customer: customers.name, phone: customers.phone })
      .from(bookings)
      .innerJoin(services, eq(bookings.serviceId, services.id))
      .innerJoin(staff, eq(bookings.staffId, staff.id))
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .where(and(eq(bookings.tenantId, tenant.id), gte(bookings.startsAt, since)))
      .orderBy(asc(bookings.startsAt))
      .limit(100),
    db
      .select({ p: payments, customer: customers.name, phone: customers.phone, service: services.name, startsAt: bookings.startsAt })
      .from(payments)
      .innerJoin(bookings, eq(payments.bookingId, bookings.id))
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .innerJoin(services, eq(bookings.serviceId, services.id))
      .where(and(eq(payments.tenantId, tenant.id), eq(payments.status, "refund_due")))
      .orderBy(desc(payments.createdAt)),
  ]);

  const groups: { day: string; items: typeof rows }[] = [];
  for (const r of rows) {
    const day = formatDay(r.b.startsAt, tenant.timezone);
    const last = groups[groups.length - 1];
    if (last?.day === day) last.items.push(r);
    else groups.push({ day, items: [r] });
  }

  return (
    <>
      <PageHead title="Bookings" sub="Upcoming appointments and the last 24 hours." />

      {refunds.length > 0 && (
        <section className="glass panel enter" style={num(1)}>
          <h2 className="panel-title">Refunds needed</h2>
          <p className="muted small" style={{ marginBottom: "0.9rem" }}>
            These customers paid, but their booking could not be confirmed. Refund them from your Paystack dashboard using the reference.
          </p>
          <ul className="list">
            {refunds.map((r) => (
              <li key={r.p.id} className="item">
                <div>
                  <div className="item-title">{r.customer}</div>
                  <div className="muted small">{r.phone}, {r.service}, {formatWhen(r.startsAt, tenant.timezone)}</div>
                  <div className="muted small">{r.p.message}</div>
                  <div className="small" style={{ overflowWrap: "anywhere" }}>Reference {r.p.reference}</div>
                </div>
                <span className="pill accent">{formatMoney(r.p.amountPesewas)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {groups.length === 0 ? (
        <section className="glass panel enter" style={num(2)}>
          <p className="muted empty-state">No bookings yet. They will show up here as soon as a customer books.</p>
        </section>
      ) : (
        groups.map((g, gi) => (
          <section key={g.day} className="glass panel enter" style={num(gi + 2)}>
            <h2 className="day-head">{g.day}</h2>
            <ul className="list">
              {g.items.map((r) => (
                <BookingCard
                  key={r.b.id}
                  b={r.b}
                  service={r.service}
                  staffName={r.staffName}
                  customer={r.customer}
                  phone={r.phone}
                  tz={tenant.timezone}
                  actions={
                    r.b.status === "confirmed" || r.b.status === "pending" ? (
                      <>
                        {r.b.status === "confirmed" && <Action id={r.b.id} status="completed" label="Mark completed" />}
                        {r.b.status === "confirmed" && <Action id={r.b.id} status="no_show" label="No-show" />}
                        <Action id={r.b.id} status="cancelled" label="Cancel" danger />
                      </>
                    ) : undefined
                  }
                />
              ))}
            </ul>
          </section>
        ))
      )}
    </>
  );
}
