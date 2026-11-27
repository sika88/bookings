import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { format } from "date-fns";
import { db } from "@/db";
import { services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";
import { basePath } from "@/lib/base";
import { depositFor } from "@/lib/bookings";
import { formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { isUuid } from "@/lib/ids";
import { Chevron } from "../icons";
import BookingForm from "./booking-form";

type SP = { service?: string; staff?: string; start?: string };

const num = (i: number) => ({ "--i": i }) as CSSProperties;

export default async function BookPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenant: string }>;
  searchParams: Promise<SP>;
}) {
  const { tenant: slug } = await params;
  const sp = await searchParams;
  const base = await basePath();
  const tenant = await getTenantBySlug(slug);
  if (!tenant) notFound();

  const startMs = Date.parse(sp.start ?? "");
  if (!sp.service || !isUuid(sp.service) || Number.isNaN(startMs)) notFound();
  const staffId = sp.staff && isUuid(sp.staff) ? sp.staff : undefined;

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, sp.service), eq(services.tenantId, tenant.id), eq(services.active, true)))
    .limit(1);
  if (!service) notFound();

  let staffName: string | null = null;
  if (staffId) {
    const [s] = await db
      .select({ name: staff.displayName })
      .from(staff)
      .where(and(eq(staff.id, staffId), eq(staff.tenantId, tenant.id)))
      .limit(1);
    staffName = s?.name ?? null;
  }

  const date = format(new TZDate(startMs, tenant.timezone), "yyyy-MM-dd");
  const slots = await getSlots({ tenant, serviceId: service.id, staffId, date });
  const stillFree = slots.some((s) => new Date(s.start).getTime() === startMs);

  const backQuery = new URLSearchParams({ service: service.id, date });
  if (staffId) backQuery.set("staff", staffId);
  const back = `${base}/?${backQuery.toString()}`;

  const deposit = depositFor(service);

  return (
    <main className="shell-narrow">
      <Link href={back} className="back enter" style={num(0)}>
        <Chevron /> Back to times
      </Link>

      <section className="glass panel enter" style={num(1)}>
        <h1 className="display h-md">{tenant.name}</h1>

        {!stillFree ? (
          <div>
            <p className="display" style={{ fontSize: "1.3rem" }}>That time is no longer available</p>
            <p className="muted" style={{ marginTop: "0.4rem", lineHeight: 1.5 }}>
              Someone may have just booked it. Pick another time and you are set.
            </p>
            <Link href={back} className="btn" style={{ marginTop: "1.25rem" }}>Choose another time</Link>
          </div>
        ) : (
          <>
            <dl className="summary">
              <div><dt>Service</dt><dd>{service.name}</dd></div>
              <div><dt>With</dt><dd>{staffName ?? "First available"}</dd></div>
              <div><dt>When</dt><dd>{formatWhen(new Date(startMs), tenant.timezone)}</dd></div>
              <div><dt>Price</dt><dd>{formatMoney(service.pricePesewas)}</dd></div>
              {deposit > 0 && <div><dt>Deposit</dt><dd>{formatMoney(deposit)}</dd></div>}
            </dl>
            {deposit > 0 && (
              <p className="note" style={{ marginTop: 0 }}>
                Your time is held for 10 minutes after you continue. Pay the deposit with Mobile Money to confirm it.
              </p>
            )}
            <BookingForm
              slug={slug}
              serviceId={service.id}
              staffId={staffId}
              start={new Date(startMs).toISOString()}
              label={deposit > 0 ? "Hold my slot" : "Confirm booking"}
            />
          </>
        )}
      </section>
    </main>
  );
}
