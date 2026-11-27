import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { basePath } from "@/lib/base";
import { HOLD_MINUTES } from "@/lib/bookings";
import { formatTime, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { cancelBooking } from "../../actions";
import { Check, Clock, Cross } from "../../icons";
import Countdown from "./countdown";

const TOKEN = /^[a-f0-9]{32}$/;
const num = (i: number) => ({ "--i": i }) as CSSProperties;

export default async function BookingPage({
  params,
}: {
  params: Promise<{ tenant: string; token: string }>;
}) {
  const { tenant: slug, token } = await params;
  const base = await basePath();
  const tenant = await getTenantBySlug(slug);
  if (!tenant || !TOKEN.test(token)) notFound();

  const [row] = await db
    .select({
      booking: bookings,
      serviceName: services.name,
      staffName: staff.displayName,
      customerName: customers.name,
    })
    .from(bookings)
    .innerJoin(services, eq(bookings.serviceId, services.id))
    .innerJoin(staff, eq(bookings.staffId, staff.id))
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .where(and(eq(bookings.manageToken, token), eq(bookings.tenantId, tenant.id)))
    .limit(1);
  if (!row) notFound();

  const b = row.booking;
  const now = Date.now();
  const holdActive = b.status === "pending" && !!b.holdExpiresAt && b.holdExpiresAt.getTime() > now;
  const holdExpired = b.status === "pending" && !holdActive;
  const canCancel = (b.status === "confirmed" || holdActive) && b.startsAt.getTime() > now;

  let title = "";
  let message = "";
  let hue = 0;
  let icon: "check" | "clock" | "cross" = "cross";

  if (b.status === "confirmed") {
    title = "You are booked";
    message = "Keep this page. You can check or cancel your booking from it.";
    hue = 150;
    icon = "check";
  } else if (holdActive) {
    title = "Your slot is on hold";
    message = `Held until ${formatTime(b.holdExpiresAt!, tenant.timezone)}. Pay the ${formatMoney(b.depositPesewas)} deposit to confirm it.`;
    hue = 38;
    icon = "clock";
  } else if (holdExpired) {
    title = "This hold has expired";
    message = "The time was released because the deposit was not paid in time.";
  } else if (b.status === "cancelled") {
    title = "This booking was cancelled";
    message = "The time has been released.";
  } else if (b.status === "completed") {
    title = "Appointment completed";
    message = "Thank you for visiting.";
    hue = 200;
    icon = "check";
  } else {
    title = "Marked as a no-show";
  }

  return (
    <main className="shell-narrow">
      <section className="glass panel enter" style={{ ...num(0), "--s": hue } as CSSProperties}>
        <div className="status-icon">
          {icon === "check" ? <Check /> : icon === "clock" ? <Clock /> : <Cross />}
        </div>
        <h1 className="display h-md" style={{ marginBottom: "0.5rem" }}>{title}</h1>
        {message && <p className="muted" style={{ lineHeight: 1.5 }}>{message}</p>}

        {holdActive && (
          <div style={{ marginTop: "1.5rem" }}>
            <Countdown
              initial={Math.max(0, Math.ceil((b.holdExpiresAt!.getTime() - now) / 1000))}
              total={HOLD_MINUTES * 60}
            />
          </div>
        )}
      </section>

      <section className="glass panel enter" style={num(1)}>
        <p className="muted small" style={{ marginBottom: "0.9rem" }}>{tenant.name}</p>
        <dl className="summary" style={{ marginBottom: 0, paddingBottom: 0, borderBottom: 0 }}>
          <div><dt>Service</dt><dd>{row.serviceName}</dd></div>
          <div><dt>With</dt><dd>{row.staffName}</dd></div>
          <div><dt>When</dt><dd>{formatWhen(b.startsAt, tenant.timezone)}</dd></div>
          <div><dt>Booked for</dt><dd>{row.customerName}</dd></div>
          <div><dt>Total</dt><dd>{formatMoney(b.totalPesewas)}</dd></div>
          {b.depositPesewas > 0 && <div><dt>Deposit</dt><dd>{formatMoney(b.depositPesewas)}</dd></div>}
        </dl>
      </section>

      <div className="enter" style={{ ...num(2), display: "grid", gap: "0.75rem" }}>
        {holdActive && (
          <button disabled className="btn">Pay with Mobile Money (coming in the next step)</button>
        )}

        {canCancel && (
          <form action={cancelBooking}>
            <input type="hidden" name="slug" value={slug} />
            <input type="hidden" name="token" value={token} />
            <button className="btn btn-danger">Cancel this booking</button>
          </form>
        )}

        {(holdExpired || b.status === "cancelled") && (
          <Link href={base || "/"} className="btn">Book another time</Link>
        )}
      </div>
    </main>
  );
}
