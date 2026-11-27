import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { addDays, format } from "date-fns";
import { db } from "@/db";
import { services, staff, staffServices } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";
import { depositFor } from "@/lib/bookings";
import { hueOf } from "@/lib/hue";
import { formatMoney } from "@/lib/money";
import { Check, Users } from "./icons";
import Pending from "./pending";

type SP = { service?: string; staff?: string; date?: string };

const num = (i: number) => ({ "--i": i }) as CSSProperties;
const hueVar = (h: number) => ({ "--ah": h }) as CSSProperties;

function href(p: SP) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(p)) if (v) q.set(k, v);
  return `?${q.toString()}`;
}

const hourOf = (label: string) => parseInt(label.slice(0, 2), 10);

function Row({ label, value, sub, state }: { label: string; value: string; sub?: string; state: "done" | "next" | "idle" }) {
  return (
    <div className={`row ${state}`}>
      <dt>{label}</dt>
      <dd>
        <span key={value} className="swap">{value}</span>
        {sub && <span className="muted small">{sub}</span>}
      </dd>
    </div>
  );
}

function StepHead({ n, title, done, hint }: { n: number; title: string; done?: boolean; hint?: string }) {
  return (
    <div className="step-head">
      <span className={`badge${done ? " done" : ""}`}>{done ? <Check /> : n}</span>
      <h2>{title}</h2>
      {hint && <span className="muted">{hint}</span>}
    </div>
  );
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
    const d = addDays(today, i);
    return {
      value: format(d, "yyyy-MM-dd"),
      weekday: i === 0 ? "Today" : format(d, "EEE"),
      num: format(d, "d"),
      month: format(d, "MMM"),
      full: format(d, "EEEE d MMMM"),
    };
  });
  const day = days.find((d) => d.value === sp.date) ?? days[0];

  const slots = service
    ? await getSlots({ tenant, serviceId: service.id, staffId: chosenStaff?.id, date: day.value })
    : [];

  const slotHref = (start: string) => {
    const q = new URLSearchParams({ service: service!.id, start });
    if (chosenStaff) q.set("staff", chosenStaff.id);
    return `/book?${q.toString()}`;
  };

  const groups = [
    { title: "Morning", items: slots.filter((s) => hourOf(s.label) < 12) },
    { title: "Afternoon", items: slots.filter((s) => hourOf(s.label) >= 12 && hourOf(s.label) < 17) },
    { title: "Evening", items: slots.filter((s) => hourOf(s.label) >= 17) },
  ].filter((g) => g.items.length > 0);
  let n = 0;

  const deposit = service ? depositFor(service) : 0;

  return (
    <main className="shell">
      <aside className="glass ticket enter" style={num(0)}>
        <div className="monogram">{tenant.name.charAt(0).toUpperCase()}</div>
        <h1 className="display brand">{tenant.name}</h1>
        <p className="muted lead">Pick a service, then a day and time. Your booking takes shape here.</p>

        <dl className="rows">
          <Row
            label="Service"
            value={service ? service.name : "Choose a service"}
            sub={service ? `${service.durationMin} min, ${formatMoney(service.pricePesewas)}` : undefined}
            state={service ? "done" : "next"}
          />
          <Row
            label="With"
            value={service ? (chosenStaff?.displayName ?? "Any available") : "Not chosen yet"}
            state={service ? "done" : "idle"}
          />
          <Row
            label="Day"
            value={service ? day.full : "Not chosen yet"}
            sub={service ? (slots.length ? `${slots.length} times open` : "Fully booked") : undefined}
            state={service ? "done" : "idle"}
          />
          <Row label="Time" value={service ? "Pick a time" : "Not chosen yet"} state={service ? "next" : "idle"} />
        </dl>

        {service && deposit > 0 && (
          <p className="note">
            A deposit of {formatMoney(deposit)} holds your slot for 10 minutes. Pay it with Mobile Money to confirm.
          </p>
        )}
      </aside>

      <div className="steps">
        <section className="glass step enter" style={num(1)}>
          <StepHead n={1} title="Choose a service" done={!!service} />
          {allServices.length === 0 ? (
            <p className="muted empty">This business has not added any services yet. Please check back soon.</p>
          ) : (
            <div className="services">
              {allServices.map((s, i) => (
                <Link
                  key={s.id}
                  href={href({ service: s.id })}
                  aria-current={service?.id === s.id ? "true" : undefined}
                  className={`tile service pop${service?.id === s.id ? " is-active" : ""}`}
                  style={num(i)}
                >
                  <div className="service-name">{s.name}</div>
                  {s.description && <p className="muted small">{s.description}</p>}
                  <div className="pills">
                    <span className="pill">{s.durationMin} min</span>
                    <span className="pill">{formatMoney(s.pricePesewas)}</span>
                    {s.depositType !== "none" && (
                      <span className="pill accent">
                        {s.depositType === "fixed" ? `${formatMoney(s.depositValue)} deposit` : `${s.depositValue}% deposit`}
                      </span>
                    )}
                  </div>
                  <span className="tick"><Check /></span>
                  <Pending />
                </Link>
              ))}
            </div>
          )}
        </section>

        {service && (
          <section className="glass step enter" style={num(0)}>
            <StepHead n={2} title="Who do you want to see?" done />
            <div className="whos">
              <Link
                href={href({ service: service.id, date: day.value })}
                aria-current={!chosenStaff ? "true" : undefined}
                className={`who pop${!chosenStaff ? " is-active" : ""}`}
                style={num(0)}
              >
                <span className="avatar any"><Users /></span>
                Any available
                <Pending />
              </Link>
              {people.map((p, i) => (
                <Link
                  key={p.id}
                  href={href({ service: service.id, staff: p.id, date: day.value })}
                  aria-current={chosenStaff?.id === p.id ? "true" : undefined}
                  className={`who pop${chosenStaff?.id === p.id ? " is-active" : ""}`}
                  style={num(i + 1)}
                >
                  <span className="avatar" style={hueVar(hueOf(p.displayName))}>{p.displayName.charAt(0).toUpperCase()}</span>
                  {p.displayName}
                  <Pending />
                </Link>
              ))}
            </div>
          </section>
        )}

        {service && (
          <section className="glass step enter" style={num(1)}>
            <StepHead n={3} title="Choose a day" done />
            <div className="days">
              {days.map((d, i) => (
                <Link
                  key={d.value}
                  href={href({ service: service.id, staff: chosenStaff?.id, date: d.value })}
                  aria-current={d.value === day.value ? "date" : undefined}
                  className={`day pop${d.value === day.value ? " is-active" : ""}`}
                  style={num(i)}
                >
                  <span className="day-name">{d.weekday}</span>
                  <span className="day-num">{d.num}</span>
                  <span className="day-mon">{d.month}</span>
                  <Pending />
                </Link>
              ))}
            </div>
          </section>
        )}

        {service && (
          <section className="glass step enter" style={num(2)}>
            <StepHead n={4} title="Pick a time" hint={day.full} />
            {groups.length === 0 ? (
              <p className="muted empty">
                No times are open on this day. Try another day, or choose a different person.
              </p>
            ) : (
              groups.map((g) => (
                <div key={g.title}>
                  <div className="group-title">
                    <span>{g.title}</span>
                    <span>{g.items.length} open</span>
                  </div>
                  <div className="slots">
                    {g.items.map((s) => (
                      <Link key={s.start} href={slotHref(s.start)} className="slot pop" style={num(Math.min(n++, 28))}>
                        {s.label}
                        <Pending />
                      </Link>
                    ))}
                  </div>
                </div>
              ))
            )}
          </section>
        )}
      </div>
    </main>
  );
}
