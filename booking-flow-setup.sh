#!/usr/bin/env bash
set -e

mkdir -p src/lib \
  "src/app/sites/[tenant]/book" \
  "src/app/sites/[tenant]/booking/[token]" \
  "src/app/dashboard/(app)/bookings"

# ---------- helpers ----------
cat > src/lib/bookings.ts <<'EOF'
import { and, eq, lt } from "drizzle-orm";
import { db } from "@/db";
import { bookings } from "@/db/schema";

export const HOLD_MINUTES = 10;

// Unpaid holds that ran out are cancelled so their slots free up.
export async function expireHolds(tenantId: string) {
  await db
    .update(bookings)
    .set({ status: "cancelled" })
    .where(
      and(
        eq(bookings.tenantId, tenantId),
        eq(bookings.status, "pending"),
        lt(bookings.holdExpiresAt, new Date()),
      ),
    );
}

export function depositFor(s: { depositType: string; depositValue: number; pricePesewas: number }) {
  if (s.depositType === "fixed") return Math.min(s.depositValue, s.pricePesewas);
  if (s.depositType === "percent") return Math.round((s.pricePesewas * s.depositValue) / 100);
  return 0;
}

// Ghana mobile numbers -> +233XXXXXXXXX, or null when invalid.
export function normalizeGhPhone(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  let national: string;
  if (digits.startsWith("233") && digits.length === 12) national = digits.slice(3);
  else if (digits.startsWith("0") && digits.length === 10) national = digits.slice(1);
  else if (digits.length === 9) national = digits;
  else return null;
  return /^[25]\d{8}$/.test(national) ? `+233${national}` : null;
}

export function pgCode(e: unknown): string | undefined {
  const err = e as { code?: string; cause?: { code?: string } };
  return err?.code ?? err?.cause?.code;
}
EOF

cat > src/lib/format.ts <<'EOF'
export function formatWhen(d: Date, tz: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    weekday: "long",
    day: "numeric",
    month: "long",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}

export function formatTime(d: Date, tz: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}
EOF

# make the slot engine free up expired holds before it looks at bookings
if ! grep -q "expireHolds" src/lib/slots.ts; then
  sed -i '1i import { expireHolds } from "@/lib/bookings";' src/lib/slots.ts
  sed -i 's#^  const tz = tenant.timezone;#  await expireHolds(tenant.id);\n  const tz = tenant.timezone;#' src/lib/slots.ts
fi
if [ "$(grep -c expireHolds src/lib/slots.ts)" -lt 2 ]; then
  echo "WARNING: could not patch src/lib/slots.ts automatically. Tell me and I'll send the edit."
fi

# ---------- public: types + actions ----------
cat > "src/app/sites/[tenant]/types.ts" <<'EOF'
export type BookingState =
  | {
      error?: string;
      values?: { name: string; phone: string; email: string; notes: string };
    }
  | undefined;
EOF

cat > "src/app/sites/[tenant]/actions.ts" <<'EOF'
"use server";

import { redirect } from "next/navigation";
import { and, count, eq, gt, inArray } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { format } from "date-fns";
import { z } from "zod";
import { db } from "@/db";
import { bookings, customers, services } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";
import { depositFor, expireHolds, HOLD_MINUTES, normalizeGhPhone, pgCode } from "@/lib/bookings";
import { isUuid } from "@/lib/ids";
import type { BookingState } from "./types";

const schema = z.object({
  slug: z.string().min(1),
  serviceId: z.string(),
  staffId: z.string().optional(),
  start: z.string(),
  name: z.string().trim().min(2, "Please enter your name").max(80, "Name is too long"),
  phone: z.string().trim().min(1, "Enter your phone number"),
  email: z.string().trim().max(120).optional(),
  notes: z.string().trim().max(300, "Notes are too long").optional(),
});

const TAKEN = "Sorry, that time was just taken. Please go back and choose another.";

export async function createBooking(_prev: BookingState, formData: FormData): Promise<BookingState> {
  const str = (k: string) => String(formData.get(k) ?? "");
  const values = { name: str("name"), phone: str("phone"), email: str("email"), notes: str("notes") };
  const fail = (error: string): BookingState => ({ error, values });

  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return fail(parsed.error.issues[0].message);
  const v = parsed.data;

  const tenant = await getTenantBySlug(v.slug);
  if (!tenant) return fail("This business is not available");
  if (!isUuid(v.serviceId)) return fail("Please choose a service");
  const staffId = v.staffId && isUuid(v.staffId) ? v.staffId : undefined;

  const phone = normalizeGhPhone(v.phone);
  if (!phone) return fail("Enter a valid Ghana mobile number, like 024 123 4567");

  const email = (v.email ?? "").trim();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return fail("Enter a valid email address");

  const startMs = Date.parse(v.start);
  if (Number.isNaN(startMs)) return fail("Invalid time");

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, v.serviceId), eq(services.tenantId, tenant.id), eq(services.active, true)))
    .limit(1);
  if (!service) return fail("That service is no longer available");

  await expireHolds(tenant.id);

  // never trust the time sent by the browser: it must still be a free slot right now
  const date = format(new TZDate(startMs, tenant.timezone), "yyyy-MM-dd");
  const slots = await getSlots({ tenant, serviceId: service.id, staffId, date });
  const slot = slots.find((s) => new Date(s.start).getTime() === startMs);
  if (!slot) return fail(TAKEN);

  // stop one phone number from hoarding slots with unpaid holds
  const [{ n }] = await db
    .select({ n: count() })
    .from(bookings)
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .where(and(eq(bookings.tenantId, tenant.id), eq(customers.phone, phone), eq(bookings.status, "pending")));
  if (n >= 3) return fail("You already have several unpaid holds. Please complete or cancel one first.");

  const [customer] = await db
    .insert(customers)
    .values({ tenantId: tenant.id, name: v.name, phone, email: email || null })
    .onConflictDoUpdate({
      target: [customers.tenantId, customers.phone],
      set: { name: v.name, ...(email ? { email } : {}) },
    })
    .returning({ id: customers.id });

  const deposit = depositFor(service);
  const startsAt = new Date(startMs);
  const endsAt = new Date(startMs + service.durationMin * 60_000);
  const blocksUntil = new Date(endsAt.getTime() + service.bufferMin * 60_000);

  let token: string | undefined;
  for (const sid of slot.staffIds) {
    try {
      const [b] = await db
        .insert(bookings)
        .values({
          tenantId: tenant.id,
          customerId: customer.id,
          serviceId: service.id,
          staffId: sid,
          startsAt,
          endsAt,
          blocksUntil,
          status: deposit > 0 ? "pending" : "confirmed",
          holdExpiresAt: deposit > 0 ? new Date(Date.now() + HOLD_MINUTES * 60_000) : null,
          totalPesewas: service.pricePesewas,
          depositPesewas: deposit,
          notes: v.notes ? v.notes : null,
        })
        .returning({ token: bookings.manageToken });
      token = b.token;
      break;
    } catch (e) {
      // 23P01 = the database refused an overlapping booking; try the next free person
      if (pgCode(e) !== "23P01") throw e;
    }
  }
  if (!token) return fail(TAKEN);

  redirect(`/booking/${token}`);
}

const TOKEN = /^[a-f0-9]{32}$/;

export async function cancelBooking(formData: FormData): Promise<void> {
  const slug = String(formData.get("slug") ?? "");
  const token = String(formData.get("token") ?? "");
  const tenant = await getTenantBySlug(slug);
  if (!tenant || !TOKEN.test(token)) return;

  await db
    .update(bookings)
    .set({ status: "cancelled" })
    .where(
      and(
        eq(bookings.tenantId, tenant.id),
        eq(bookings.manageToken, token),
        inArray(bookings.status, ["pending", "confirmed"]),
        gt(bookings.startsAt, new Date()),
      ),
    );

  redirect(`/booking/${token}`);
}
EOF

# ---------- public: home page with clickable slots ----------
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
import { depositLabel, formatMoney } from "@/lib/money";

type SP = { service?: string; staff?: string; date?: string };

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

  const slotHref = (start: string) => {
    const q = new URLSearchParams({ service: service!.id, start });
    if (chosenStaff) q.set("staff", chosenStaff.id);
    return `/book?${q.toString()}`;
  };

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
                  {s.durationMin} min · {formatMoney(s.pricePesewas)} · {depositLabel(s.depositType, s.depositValue)}
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
          <h2 className="mb-3 font-medium">4. Pick a time</h2>
          {slots.length === 0 ? (
            <p className="text-sm text-neutral-500">No times available on this day. Try another day.</p>
          ) : (
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
              {slots.map((s) => (
                <Link
                  key={s.start}
                  href={slotHref(s.start)}
                  className="rounded border px-3 py-2 text-center text-sm hover:bg-black hover:text-white"
                >
                  {s.label}
                </Link>
              ))}
            </div>
          )}
        </section>
      )}
    </main>
  );
}
EOF

# ---------- public: details form ----------
cat > "src/app/sites/[tenant]/book/booking-form.tsx" <<'EOF'
"use client";

import { useActionState } from "react";
import { createBooking } from "../actions";
import type { BookingState } from "../types";

const box = "mt-1 w-full rounded border p-2";

export default function BookingForm({
  slug,
  serviceId,
  staffId,
  start,
  label,
}: {
  slug: string;
  serviceId: string;
  staffId?: string;
  start: string;
  label: string;
}) {
  const [state, action, pending] = useActionState<BookingState, FormData>(createBooking, undefined);
  const v = state?.values;

  return (
    <form action={action} className="space-y-3">
      <input type="hidden" name="slug" value={slug} />
      <input type="hidden" name="serviceId" value={serviceId} />
      {staffId && <input type="hidden" name="staffId" value={staffId} />}
      <input type="hidden" name="start" value={start} />

      <label className="block text-sm">
        Your name
        <input name="name" required autoComplete="name" defaultValue={v?.name} className={box} />
      </label>
      <label className="block text-sm">
        Phone number
        <input name="phone" type="tel" required autoComplete="tel" placeholder="024 123 4567" defaultValue={v?.phone} className={box} />
      </label>
      <label className="block text-sm">
        Email (optional)
        <input name="email" type="email" autoComplete="email" defaultValue={v?.email} className={box} />
      </label>
      <label className="block text-sm">
        Notes (optional)
        <textarea name="notes" rows={2} defaultValue={v?.notes} className={box} />
      </label>
      <p className="text-xs text-neutral-500">We will text your confirmation and reminders to this number.</p>

      {state?.error && <p className="text-sm text-red-600">{state.error}</p>}
      <button disabled={pending} className="w-full rounded bg-black p-3 text-white disabled:opacity-50">
        {pending ? "Booking..." : label}
      </button>
    </form>
  );
}
EOF

cat > "src/app/sites/[tenant]/book/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { format } from "date-fns";
import { db } from "@/db";
import { services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";
import { depositFor } from "@/lib/bookings";
import { formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { isUuid } from "@/lib/ids";
import BookingForm from "./booking-form";

type SP = { service?: string; staff?: string; start?: string };

export default async function BookPage({
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
  const back = `/?${backQuery.toString()}`;

  const deposit = depositFor(service);

  return (
    <main className="mx-auto max-w-md space-y-6 p-6 sm:p-8">
      <Link href={back} className="text-sm underline">← Back to times</Link>
      <h1 className="text-2xl font-semibold">{tenant.name}</h1>

      {!stillFree ? (
        <div className="rounded border p-4 text-sm">
          <p className="font-medium">That time is no longer available.</p>
          <p className="mt-1 text-neutral-500">Someone may have just booked it. Please pick another time.</p>
          <Link href={back} className="mt-3 inline-block underline">Choose another time</Link>
        </div>
      ) : (
        <>
          <div className="space-y-1 rounded border p-4 text-sm">
            <div className="font-medium">{service.name}{staffName ? ` with ${staffName}` : ""}</div>
            <div>{formatWhen(new Date(startMs), tenant.timezone)}</div>
            <div className="text-neutral-500">
              {service.durationMin} min · {formatMoney(service.pricePesewas)}
            </div>
            {deposit > 0 && (
              <div className="text-neutral-500">
                Deposit to confirm: {formatMoney(deposit)}. Your time is held for 10 minutes after you continue.
              </div>
            )}
          </div>
          <BookingForm
            slug={slug}
            serviceId={service.id}
            staffId={staffId}
            start={new Date(startMs).toISOString()}
            label={deposit > 0 ? "Hold my slot" : "Confirm booking"}
          />
        </>
      )}
    </main>
  );
}
EOF

# ---------- public: booking status page ----------
cat > "src/app/sites/[tenant]/booking/[token]/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { formatTime, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { cancelBooking } from "../../actions";

const TOKEN = /^[a-f0-9]{32}$/;

export default async function BookingPage({
  params,
}: {
  params: Promise<{ tenant: string; token: string }>;
}) {
  const { tenant: slug, token } = await params;
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
  if (b.status === "confirmed") {
    title = "Your booking is confirmed";
    message = "See you then. Keep this page to check or cancel your booking.";
  } else if (holdActive) {
    title = "Your slot is on hold";
    message = `Held until ${formatTime(b.holdExpiresAt!, tenant.timezone)}. Pay the deposit of ${formatMoney(b.depositPesewas)} to confirm it.`;
  } else if (holdExpired) {
    title = "This hold has expired";
    message = "The time was released because the deposit was not paid in time.";
  } else if (b.status === "cancelled") {
    title = "This booking was cancelled";
    message = "If the deposit was never paid, the time was simply released.";
  } else if (b.status === "completed") {
    title = "Appointment completed";
    message = "Thank you for visiting.";
  } else {
    title = "Marked as a no-show";
    message = "";
  }

  return (
    <main className="mx-auto max-w-md space-y-6 p-6 sm:p-8">
      <h1 className="text-2xl font-semibold">{tenant.name}</h1>

      <div className="rounded border p-4">
        <h2 className="font-medium">{title}</h2>
        {message && <p className="mt-1 text-sm text-neutral-500">{message}</p>}
      </div>

      <div className="space-y-1 rounded border p-4 text-sm">
        <div className="font-medium">{row.serviceName} with {row.staffName}</div>
        <div>{formatWhen(b.startsAt, tenant.timezone)}</div>
        <div className="text-neutral-500">Booked for {row.customerName}</div>
        <div className="text-neutral-500">
          Total {formatMoney(b.totalPesewas)}
          {b.depositPesewas > 0 ? ` · Deposit ${formatMoney(b.depositPesewas)}` : ""}
        </div>
      </div>

      {holdActive && (
        <button disabled className="w-full rounded bg-black p-3 text-white opacity-40">
          Pay deposit with Mobile Money (coming in the next step)
        </button>
      )}

      {canCancel && (
        <form action={cancelBooking}>
          <input type="hidden" name="slug" value={slug} />
          <input type="hidden" name="token" value={token} />
          <button className="text-sm text-red-600 underline">Cancel this booking</button>
        </form>
      )}

      {(holdExpired || b.status === "cancelled") && (
        <Link href="/" className="inline-block underline">Book another time</Link>
      )}
    </main>
  );
}
EOF

# ---------- dashboard: bookings list ----------
cat > "src/app/dashboard/(app)/bookings/actions.ts" <<'EOF'
"use server";

import { revalidatePath } from "next/cache";
import { and, eq, inArray } from "drizzle-orm";
import { db } from "@/db";
import { bookings } from "@/db/schema";
import { canManage, requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";

export async function setBookingStatus(formData: FormData): Promise<void> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return;

  const id = String(formData.get("id") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!isUuid(id)) return;

  if (status === "cancelled") {
    await db
      .update(bookings)
      .set({ status: "cancelled" })
      .where(and(eq(bookings.id, id), eq(bookings.tenantId, tenant.id), inArray(bookings.status, ["pending", "confirmed"])));
  } else if (status === "completed" || status === "no_show") {
    await db
      .update(bookings)
      .set({ status })
      .where(and(eq(bookings.id, id), eq(bookings.tenantId, tenant.id), eq(bookings.status, "confirmed")));
  }

  revalidatePath("/dashboard", "layout");
}
EOF

cat > "src/app/dashboard/(app)/bookings/page.tsx" <<'EOF'
import { and, asc, eq, gte } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { expireHolds } from "@/lib/bookings";
import { formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { setBookingStatus } from "./actions";

const LABEL: Record<string, string> = {
  pending: "Awaiting deposit",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
  completed: "Completed",
  no_show: "No-show",
};

function Action({ id, status, label }: { id: string; status: string; label: string }) {
  return (
    <form action={setBookingStatus}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="status" value={status} />
      <button className="underline">{label}</button>
    </form>
  );
}

export default async function BookingsPage() {
  const { tenant } = await requireTenant();
  await expireHolds(tenant.id);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const rows = await db
    .select({
      b: bookings,
      service: services.name,
      staffName: staff.displayName,
      customer: customers.name,
      phone: customers.phone,
    })
    .from(bookings)
    .innerJoin(services, eq(bookings.serviceId, services.id))
    .innerJoin(staff, eq(bookings.staffId, staff.id))
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .where(and(eq(bookings.tenantId, tenant.id), gte(bookings.startsAt, since)))
    .orderBy(asc(bookings.startsAt))
    .limit(100);

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-semibold">Bookings</h1>
      <p className="text-sm text-neutral-500">Upcoming appointments and the last 24 hours.</p>
      {rows.length === 0 && <p className="text-sm text-neutral-500">No bookings yet.</p>}
      <ul className="space-y-2">
        {rows.map(({ b, service, staffName, customer, phone }) => (
          <li key={b.id} className={`rounded border p-4 ${b.status === "cancelled" ? "opacity-50" : ""}`}>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <div className="font-medium">{formatWhen(b.startsAt, tenant.timezone)}</div>
                <div className="text-sm">{service} with {staffName}</div>
                <div className="text-sm text-neutral-500">{customer} · {phone}</div>
                {b.notes && <div className="text-sm text-neutral-500">Note: {b.notes}</div>}
              </div>
              <div className="text-right text-sm">
                <div className="font-medium">{LABEL[b.status] ?? b.status}</div>
                <div className="text-neutral-500">
                  {formatMoney(b.totalPesewas)}
                  {b.depositPesewas > 0 ? ` · deposit ${formatMoney(b.depositPesewas)}` : ""}
                </div>
              </div>
            </div>
            <div className="mt-3 flex gap-4 text-sm">
              {b.status === "confirmed" && <Action id={b.id} status="completed" label="Mark completed" />}
              {b.status === "confirmed" && <Action id={b.id} status="no_show" label="No-show" />}
              {(b.status === "confirmed" || b.status === "pending") && <Action id={b.id} status="cancelled" label="Cancel" />}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
EOF

# ---------- nav link ----------
LAYOUT="src/app/dashboard/(app)/layout.tsx"
if ! grep -q 'href="/bookings"' "$LAYOUT"; then
  sed -i 's#<Link href="/staff">Staff</Link>#<Link href="/staff">Staff</Link>\n          <Link href="/bookings">Bookings</Link>#' "$LAYOUT"
fi

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
