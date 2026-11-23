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
