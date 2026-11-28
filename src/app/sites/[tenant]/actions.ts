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
import { onBookingCancelled, onBookingConfirmed } from "@/lib/messaging";
import { basePath } from "@/lib/base";
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
        .returning({ token: bookings.manageToken, id: bookings.id, status: bookings.status });
      token = b.token;
      if (b.status === "confirmed") await onBookingConfirmed(b.id);
      break;
    } catch (e) {
      // 23P01 = the database refused an overlapping booking; try the next free person
      if (pgCode(e) !== "23P01") throw e;
    }
  }
  if (!token) return fail(TAKEN);

  redirect(`${await basePath()}/booking/${token}`);
}

const TOKEN = /^[a-f0-9]{32}$/;

export async function cancelBooking(formData: FormData): Promise<void> {
  const slug = String(formData.get("slug") ?? "");
  const token = String(formData.get("token") ?? "");
  const tenant = await getTenantBySlug(slug);
  if (!tenant || !TOKEN.test(token)) return;

  const cancelled = await db
    .update(bookings)
    .set({ status: "cancelled" })
    .where(
      and(
        eq(bookings.tenantId, tenant.id),
        eq(bookings.manageToken, token),
        inArray(bookings.status, ["pending", "confirmed"]),
        gt(bookings.startsAt, new Date()),
      ),
    )
    .returning({ id: bookings.id });

  for (const c of cancelled) await onBookingCancelled(c.id);

  redirect(`${await basePath()}/booking/${token}`);
}
