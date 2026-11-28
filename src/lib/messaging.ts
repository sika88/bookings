import { after } from "next/server";
import { and, asc, eq, inArray, isNull, lt, lte, or } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, messages, services, tenants } from "@/db/schema";
import { sendSms, smsConfigured } from "./sms";

const HOUR = 3_600_000;
const MAX_ATTEMPTS = 3;

type Kind = "confirmation" | "reminder_24h" | "reminder_2h" | "cancellation";

// Absolute link that works from a cron job, where there is no request to read a host from.
export function bookingLink(slug: string, token: string) {
  const rootFull = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
  if (rootFull && !rootFull.startsWith("localhost")) return `https://${slug}.${rootFull}/booking/${token}`;
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}/b/${slug}/booking/${token}`;
  }
  return `http://${slug}.localhost:3000/booking/${token}`;
}

// Plain ASCII keeps a text in one GSM-7 segment (160 chars) instead of the 70-char Unicode format.
const ascii = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\x20-\x7E]/g, "")
    .replace(/\s+/g, " ")
    .trim();

const ymd = (d: Date, tz: string) =>
  new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);

const shortDate = (d: Date, tz: string) =>
  new Intl.DateTimeFormat("en-GB", { timeZone: tz, weekday: "short", day: "numeric", month: "short" }).format(d);

const clock = (d: Date, tz: string) =>
  new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false }).format(d);

function dayWord(start: Date, now: Date, tz: string) {
  const s = ymd(start, tz);
  if (s === ymd(now, tz)) return "today";
  if (s === ymd(new Date(now.getTime() + 24 * HOUR), tz)) return "tomorrow";
  return shortDate(start, tz);
}

function render(
  kind: Kind,
  d: { business: string; first: string; service: string; start: Date; now: Date; tz: string; link: string },
) {
  const date = shortDate(d.start, d.tz);
  const time = clock(d.start, d.tz);
  let text: string;

  switch (kind) {
    case "confirmation":
      text = `${d.business}: Hi ${d.first}, your ${d.service} is booked for ${date} at ${time}. Manage or cancel: ${d.link}`;
      break;
    case "reminder_24h":
    case "reminder_2h":
      text = `Reminder from ${d.business}: your ${d.service} is ${dayWord(d.start, d.now, d.tz)} at ${time}.${kind === "reminder_2h" ? " See you soon!" : ""} Details: ${d.link}`;
      break;
    case "cancellation":
      text = `${d.business}: your ${d.service} on ${date} at ${time} was cancelled. Book again: ${d.link}`;
      break;
  }
  return ascii(text);
}

// Send confirmations right after the response; reminders are picked up by the cron endpoint.
function kick() {
  const run = async () => {
    try {
      await processDueMessages();
    } catch (e) {
      console.error("[messaging] processing failed", e);
    }
  };
  try {
    after(run);
  } catch {
    void run();
  }
}

// Call when a booking becomes confirmed. Never throws: texts must not break booking or payment.
export async function onBookingConfirmed(bookingId: string) {
  try {
    const [row] = await db
      .select({ b: bookings, optIn: customers.smsOptIn, enabled: tenants.smsEnabled })
      .from(bookings)
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .innerJoin(tenants, eq(bookings.tenantId, tenants.id))
      .where(eq(bookings.id, bookingId))
      .limit(1);
    if (!row || row.b.status !== "confirmed" || !row.enabled || !row.optIn) return;

    const now = Date.now();
    const start = row.b.startsAt.getTime();
    const plan: { kind: Kind; sendAt: Date }[] = [{ kind: "confirmation", sendAt: new Date(now) }];
    if (start - 24 * HOUR > now + 10 * 60_000) plan.push({ kind: "reminder_24h", sendAt: new Date(start - 24 * HOUR) });
    if (start - 2 * HOUR > now + 10 * 60_000) plan.push({ kind: "reminder_2h", sendAt: new Date(start - 2 * HOUR) });

    await db
      .insert(messages)
      .values(plan.map((p) => ({ tenantId: row.b.tenantId, bookingId, kind: p.kind, sendAt: p.sendAt })))
      .onConflictDoNothing();
    kick();
  } catch (e) {
    console.error("[messaging] could not queue confirmation", e);
  }
}

// Call when a booking is cancelled. Drops unsent texts, and tells the customer if we had confirmed with them.
export async function onBookingCancelled(bookingId: string) {
  try {
    await db
      .update(messages)
      .set({ status: "skipped", lastError: "Booking was cancelled", claimedAt: null })
      .where(
        and(
          eq(messages.bookingId, bookingId),
          eq(messages.status, "pending"),
          inArray(messages.kind, ["confirmation", "reminder_24h", "reminder_2h"]),
        ),
      );

    const [told] = await db
      .select({ id: messages.id })
      .from(messages)
      .where(and(eq(messages.bookingId, bookingId), eq(messages.kind, "confirmation"), eq(messages.status, "sent")))
      .limit(1);
    if (!told) return;

    const [row] = await db
      .select({ b: bookings, enabled: tenants.smsEnabled })
      .from(bookings)
      .innerJoin(tenants, eq(bookings.tenantId, tenants.id))
      .where(eq(bookings.id, bookingId))
      .limit(1);
    if (!row || !row.enabled || row.b.startsAt.getTime() <= Date.now()) return;

    await db
      .insert(messages)
      .values({ tenantId: row.b.tenantId, bookingId, kind: "cancellation", sendAt: new Date() })
      .onConflictDoNothing();
    kick();
  } catch (e) {
    console.error("[messaging] could not queue cancellation", e);
  }
}

// Atomically claim due rows so two runners never send the same text.
async function claim(limit: number) {
  const now = new Date();
  const stale = new Date(now.getTime() - 5 * 60_000);
  const free = or(isNull(messages.claimedAt), lt(messages.claimedAt, stale));

  const due = await db
    .select({ id: messages.id })
    .from(messages)
    .where(and(eq(messages.status, "pending"), lte(messages.sendAt, now), free))
    .orderBy(asc(messages.sendAt))
    .limit(limit);
  if (due.length === 0) return [];

  return db
    .update(messages)
    .set({ claimedAt: now })
    .where(and(inArray(messages.id, due.map((d) => d.id)), eq(messages.status, "pending"), free))
    .returning({ id: messages.id });
}

async function processOne(id: string): Promise<"sent" | "failed" | "skipped" | "retry"> {
  const [row] = await db
    .select({ m: messages, b: bookings, c: customers, service: services.name, t: tenants })
    .from(messages)
    .innerJoin(bookings, eq(messages.bookingId, bookings.id))
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .innerJoin(services, eq(bookings.serviceId, services.id))
    .innerJoin(tenants, eq(messages.tenantId, tenants.id))
    .where(eq(messages.id, id))
    .limit(1);
  if (!row) return "skipped";

  const { m, b, c, t } = row;
  const now = new Date();

  const skip = async (reason: string) => {
    await db.update(messages).set({ status: "skipped", lastError: reason, claimedAt: null }).where(eq(messages.id, m.id));
    return "skipped" as const;
  };

  if (!t.smsEnabled || !c.smsOptIn) return skip("SMS is turned off");
  if (m.kind === "cancellation") {
    if (b.status !== "cancelled") return skip("Booking is not cancelled");
  } else {
    if (b.status !== "confirmed") return skip("Booking is not confirmed");
    if (b.startsAt.getTime() <= now.getTime()) return skip("Appointment has already started");
  }
  if (!smsConfigured()) return skip("SMS provider is not configured");

  const body = render(m.kind, {
    business: t.name,
    first: c.name.trim().split(/\s+/)[0] ?? "there",
    service: row.service,
    start: b.startsAt,
    now,
    tz: t.timezone,
    link: bookingLink(t.slug, b.manageToken),
  });

  const r = await sendSms(c.phone, body);
  if (r.ok) {
    await db
      .update(messages)
      .set({ status: "sent", sentAt: now, providerId: r.id ?? null, body, toPhone: c.phone, attempts: m.attempts + 1, lastError: null, claimedAt: null })
      .where(eq(messages.id, m.id));
    return "sent";
  }

  const attempts = m.attempts + 1;
  if (r.retryable && attempts < MAX_ATTEMPTS) {
    await db
      .update(messages)
      .set({ attempts, lastError: r.error, sendAt: new Date(now.getTime() + attempts * 5 * 60_000), claimedAt: null })
      .where(eq(messages.id, m.id));
    return "retry";
  }

  await db
    .update(messages)
    .set({ status: "failed", attempts, lastError: r.error, body, toPhone: c.phone, claimedAt: null })
    .where(eq(messages.id, m.id));
  return "failed";
}

// Sends everything that is due, within a time budget so serverless functions are not cut off.
export async function processDueMessages(budgetMs = 8000) {
  const t0 = Date.now();
  const out = { sent: 0, failed: 0, skipped: 0, retry: 0 };

  while (Date.now() - t0 < budgetMs) {
    const batch = await claim(3);
    if (batch.length === 0) break;
    for (const { id } of batch) out[await processOne(id)]++;
  }
  return out;
}
