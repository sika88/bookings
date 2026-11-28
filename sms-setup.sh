#!/usr/bin/env bash
set -e

mkdir -p src/lib src/db/schema src/app/api/cron/messages \
  "src/app/dashboard/(app)/settings" "src/app/dashboard/(app)/bookings"

# ================= database =================
cat > src/db/schema/tenants.ts <<'EOF'
import { boolean, pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

export const tenantType = pgEnum("tenant_type", ["salon", "clinic", "barber", "venue"]);

export const tenants = pgTable("tenants", {
  id: uuid("id").primaryKey().defaultRandom(),
  slug: text("slug").notNull().unique(),
  name: text("name").notNull(),
  type: tenantType("type").notNull(),
  timezone: text("timezone").notNull().default("Africa/Accra"),
  currency: text("currency").notNull().default("GHS"),
  status: text("status").notNull().default("active"),
  smsEnabled: boolean("sms_enabled").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
EOF

cat > src/db/schema/messages.ts <<'EOF'
import { index, integer, pgEnum, pgTable, text, timestamp, unique, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";
import { bookings } from "./booking";

export const messageKind = pgEnum("message_kind", ["confirmation", "reminder_24h", "reminder_2h", "cancellation"]);
export const messageStatus = pgEnum("message_status", ["pending", "sent", "failed", "skipped"]);

// Outbox: one row per text we intend to send. Unique per booking + kind, so nothing is sent twice.
export const messages = pgTable(
  "messages",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    bookingId: uuid("booking_id").notNull().references(() => bookings.id),
    kind: messageKind("kind").notNull(),
    status: messageStatus("status").notNull().default("pending"),
    sendAt: timestamp("send_at", { withTimezone: true }).notNull(),
    claimedAt: timestamp("claimed_at", { withTimezone: true }),
    attempts: integer("attempts").notNull().default(0),
    lastError: text("last_error"),
    toPhone: text("to_phone"),
    body: text("body"),
    providerId: text("provider_id"),
    sentAt: timestamp("sent_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    unique("messages_booking_kind_uq").on(t.bookingId, t.kind),
    index("messages_due_idx").on(t.status, t.sendAt),
    index("messages_tenant_idx").on(t.tenantId, t.createdAt),
  ],
);
EOF

cat > src/db/schema/index.ts <<'EOF'
export * from "./tenants";
export * from "./auth";
export * from "./memberships";
export * from "./booking";
export * from "./payments";
export * from "./slug-history";
export * from "./messages";
EOF

# ================= SMS provider (swap this file to change provider) =================
cat > src/lib/sms.ts <<'EOF'
export type SmsResult = { ok: true; id?: string } | { ok: false; error: string; retryable: boolean };

const dryRun = () => process.env.SMS_DRY_RUN === "true";

export const smsConfigured = () =>
  dryRun() || (!!process.env.ARKESEL_API_KEY && !process.env.ARKESEL_API_KEY.includes("PASTE_YOUR"));

// to: +233XXXXXXXXX
export async function sendSms(to: string, message: string): Promise<SmsResult> {
  if (dryRun()) {
    console.log(`[sms dry run] to ${to}: ${message}`);
    return { ok: true, id: "dry-run" };
  }

  const key = process.env.ARKESEL_API_KEY;
  const sender = process.env.SMS_SENDER_ID;
  if (!key || !sender) return { ok: false, error: "ARKESEL_API_KEY or SMS_SENDER_ID is missing", retryable: false };

  try {
    const res = await fetch("https://sms.arkesel.com/api/v2/sms/send", {
      method: "POST",
      headers: { "api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({ sender, message, recipients: [to.replace(/^\+/, "")] }),
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
    const json = (await res.json().catch(() => null)) as
      | { status?: string; message?: string; data?: { id?: string }[] }
      | null;

    if (res.ok && json?.status === "success") return { ok: true, id: json.data?.[0]?.id };
    return {
      ok: false,
      error: json?.message ?? `HTTP ${res.status}`,
      retryable: res.status >= 500 || res.status === 429,
    };
  } catch {
    return { ok: false, error: "Could not reach the SMS provider", retryable: true };
  }
}
EOF

# ================= messaging: enqueue + send =================
cat > src/lib/messaging.ts <<'EOF'
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
EOF

# ================= cron endpoint =================
cat > src/app/api/cron/messages/route.ts <<'EOF'
import { timingSafeEqual } from "node:crypto";
import { processDueMessages } from "@/lib/messaging";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function authorised(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const sent = Buffer.from(req.headers.get("authorization") ?? "");
  const want = Buffer.from(`Bearer ${secret}`);
  return sent.length === want.length && timingSafeEqual(sent, want);
}

async function run(req: Request) {
  if (!authorised(req)) return new Response("Unauthorized", { status: 401 });
  return Response.json(await processDueMessages());
}

export const GET = run;
export const POST = run;
EOF

# helper for testing reminders without waiting
cat > src/db/sms-flush.ts <<'EOF'
import { eq } from "drizzle-orm";
import { db } from "./index";
import { messages } from "./schema";

async function main() {
  const rows = await db
    .update(messages)
    .set({ sendAt: new Date(), claimedAt: null })
    .where(eq(messages.status, "pending"))
    .returning({ id: messages.id });
  console.log(`Moved ${rows.length} pending message(s) to now. Call the cron URL to send them.`);
}
main();
EOF
npm pkg set scripts.db:sms:flush="tsx --env-file=.env.local src/db/sms-flush.ts"

# ================= dashboard: cancel hook =================
cat > "src/app/dashboard/(app)/bookings/actions.ts" <<'EOF'
"use server";

import { revalidatePath } from "next/cache";
import { and, eq, inArray } from "drizzle-orm";
import { db } from "@/db";
import { bookings } from "@/db/schema";
import { canManage, requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import { onBookingCancelled } from "@/lib/messaging";

export async function setBookingStatus(formData: FormData): Promise<void> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return;

  const id = String(formData.get("id") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!isUuid(id)) return;

  if (status === "cancelled") {
    const done = await db
      .update(bookings)
      .set({ status: "cancelled" })
      .where(and(eq(bookings.id, id), eq(bookings.tenantId, tenant.id), inArray(bookings.status, ["pending", "confirmed"])))
      .returning({ id: bookings.id });
    for (const d of done) await onBookingCancelled(d.id);
  } else if (status === "completed" || status === "no_show") {
    await db
      .update(bookings)
      .set({ status })
      .where(and(eq(bookings.id, id), eq(bookings.tenantId, tenant.id), eq(bookings.status, "confirmed")));
  }

  revalidatePath("/dashboard", "layout");
}
EOF

# ================= dashboard: settings (adds the text-message panel) =================
cat > "src/app/dashboard/(app)/settings/actions.ts" <<'EOF'
"use server";

import { revalidatePath } from "next/cache";
import { and, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db";
import { tenants, tenantSlugHistory } from "@/db/schema";
import { pgCode } from "@/lib/bookings";
import { canManage, requireTenant } from "@/lib/context";
import { checkSlug } from "@/lib/slug";
import type { ActionState } from "@/components/action-form";

export async function updateBusiness(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: "You don't have permission to do this" };

  const parsed = z
    .object({ name: z.string().trim().min(2, "Business name is too short").max(80, "Business name is too long") })
    .safeParse({ name: formData.get("name") });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  await db.update(tenants).set({ name: parsed.data.name }).where(eq(tenants.id, tenant.id));
  revalidatePath("/dashboard", "layout");
  return { ok: true };
}

export async function updateSms(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: "You don't have permission to do this" };

  await db.update(tenants).set({ smsEnabled: formData.get("smsEnabled") === "on" }).where(eq(tenants.id, tenant.id));
  revalidatePath("/dashboard", "layout");
  return { ok: true };
}

export async function updateAddress(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (role !== "owner") return { error: "Only the owner can change the booking address" };

  const r = await checkSlug(String(formData.get("slug") ?? ""), tenant.id);
  if ("error" in r) return { error: r.error };

  // one atomic step: free the new name if it was ours before, switch, and remember the old one
  const reclaim = db
    .delete(tenantSlugHistory)
    .where(and(eq(tenantSlugHistory.slug, r.slug), eq(tenantSlugHistory.tenantId, tenant.id)));
  const rename = db.update(tenants).set({ slug: r.slug }).where(eq(tenants.id, tenant.id));
  const remember = db.insert(tenantSlugHistory).values({ tenantId: tenant.id, slug: tenant.slug });

  try {
    await db.batch([reclaim, rename, remember]);
  } catch (e) {
    if (pgCode(e) === "23505") return { error: "That address was just taken. Try another." };
    throw e;
  }

  revalidatePath("/dashboard", "layout");
  return { ok: true };
}
EOF

cat > "src/app/dashboard/(app)/settings/page.tsx" <<'EOF'
import { desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, messages, tenantSlugHistory } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { publicUrl, requireTenant } from "@/lib/context";
import { num, statusHue } from "@/lib/css";
import { formatWhen } from "@/lib/format";
import PageHead from "../page-head";
import { updateAddress, updateBusiness, updateSms } from "./actions";

const KIND: Record<string, string> = {
  confirmation: "Confirmation",
  reminder_24h: "24-hour reminder",
  reminder_2h: "2-hour reminder",
  cancellation: "Cancellation notice",
};
const STATE: Record<string, { label: string; hue: number }> = {
  sent: { label: "Sent", hue: 150 },
  pending: { label: "Scheduled", hue: 38 },
  failed: { label: "Failed", hue: 0 },
  skipped: { label: "Skipped", hue: 220 },
};

export default async function SettingsPage() {
  const { tenant, role } = await requireTenant();

  const [history, recent, url, sample] = await Promise.all([
    db.select().from(tenantSlugHistory).where(eq(tenantSlugHistory.tenantId, tenant.id)).orderBy(desc(tenantSlugHistory.createdAt)),
    db
      .select({ m: messages, customer: customers.name })
      .from(messages)
      .innerJoin(bookings, eq(messages.bookingId, bookings.id))
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .where(eq(messages.tenantId, tenant.id))
      .orderBy(desc(messages.createdAt))
      .limit(8),
    publicUrl(tenant.slug),
    publicUrl("SLUG"),
  ]);
  const [prefix, suffix] = sample.replace(/^https?:\/\//, "").split("SLUG");

  return (
    <>
      <PageHead title="Settings" sub="Your business details, text messages and booking page address." />

      <section className="glass panel enter" style={{ ...num(1), maxWidth: "44rem" }}>
        <h2 className="panel-title">Business</h2>
        <ActionForm action={updateBusiness} submitLabel="Save name">
          <label>
            Business name
            <input name="name" required defaultValue={tenant.name} className="field" />
          </label>
        </ActionForm>
      </section>

      <section className="glass panel enter" style={{ ...num(2), maxWidth: "44rem" }}>
        <h2 className="panel-title">Text messages</h2>
        <ActionForm action={updateSms} submitLabel="Save">
          <label className="switch">
            <input type="checkbox" name="smsEnabled" defaultChecked={tenant.smsEnabled} />
            <span className="track" aria-hidden="true" />
            Text customers about their bookings
          </label>
          <p className="muted small">
            Customers get a confirmation when their booking is confirmed, reminders 24 hours and 2 hours before, and a notice if it is cancelled.
          </p>
        </ActionForm>

        <div style={{ marginTop: "1.5rem" }}>
          <div className="muted small" style={{ marginBottom: "0.6rem" }}>Recent messages</div>
          {recent.length === 0 ? (
            <p className="muted small">Nothing sent yet. Messages appear here once customers book.</p>
          ) : (
            <ul className="list">
              {recent.map(({ m, customer }) => {
                const st = STATE[m.status] ?? { label: m.status, hue: 220 };
                return (
                  <li key={m.id} className="item">
                    <div>
                      <div className="item-title" style={{ fontSize: "1rem" }}>{KIND[m.kind] ?? m.kind}</div>
                      <div className="muted small">{customer}, {formatWhen(m.sentAt ?? m.sendAt, tenant.timezone)}</div>
                      {m.lastError && m.status !== "sent" && <div className="muted small">{m.lastError}</div>}
                    </div>
                    <span className="status" style={statusHue(st.hue)}>{st.label}</span>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>

      <section className="glass panel enter" style={{ ...num(3), maxWidth: "44rem" }}>
        <h2 className="panel-title">Booking page address</h2>
        <p className="muted small" style={{ marginBottom: "1rem" }}>
          Customers book at{" "}
          <a href={url} target="_blank" rel="noreferrer" className="link">{url}</a>
        </p>

        {role === "owner" ? (
          <ActionForm action={updateAddress} submitLabel="Change address">
            <label>
              New address
              <div className="field-group">
                {prefix && <span className="suffix" style={{ paddingLeft: "0.95rem" }}>{prefix}</span>}
                <input name="slug" required defaultValue={tenant.slug} autoCapitalize="none" spellCheck={false} />
                {suffix && <span className="suffix">{suffix}</span>}
              </div>
            </label>
            <p className="muted small">
              Use 3 to 40 letters, numbers or single hyphens. Changing it is safe: your old address keeps working and redirects to the new one, so links you have already shared or texted still open the right page. Old addresses stay reserved for you.
            </p>
          </ActionForm>
        ) : (
          <p className="muted small">Only the owner can change the booking address.</p>
        )}

        {history.length > 0 && (
          <div style={{ marginTop: "1.5rem" }}>
            <div className="muted small" style={{ marginBottom: "0.5rem" }}>Old addresses (redirecting here)</div>
            <div className="pills">
              {history.map((h) => (
                <span key={h.id} className="pill">{h.slug}</span>
              ))}
            </div>
          </div>
        )}
      </section>
    </>
  );
}
EOF

# ================= hook into the booking and payment flows =================
cat > .cancel.tmp <<'EOF'
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
EOF

cat > patch-sms.mjs <<'PATCH_EOF'
import { readFileSync, writeFileSync } from "node:fs";

function must(s, from, to, file) {
  if (!s.includes(from)) throw new Error(`Could not find this text in ${file}:\n${from}`);
  return s.replace(from, () => to);
}

{
  const file = "src/app/sites/[tenant]/actions.ts";
  let s = readFileSync(file, "utf8");
  if (s.includes("@/lib/messaging")) {
    console.log("already patched:", file);
  } else {
    s = must(s, 'import { isUuid } from "@/lib/ids";', 'import { isUuid } from "@/lib/ids";\nimport { onBookingCancelled, onBookingConfirmed } from "@/lib/messaging";', file);
    s = must(s, ".returning({ token: bookings.manageToken });", ".returning({ token: bookings.manageToken, id: bookings.id, status: bookings.status });", file);
    s = must(s, "token = b.token;", 'token = b.token;\n      if (b.status === "confirmed") await onBookingConfirmed(b.id);', file);
    const i = s.indexOf("export async function cancelBooking");
    if (i < 0) throw new Error(`Could not find cancelBooking in ${file}`);
    s = s.slice(0, i) + readFileSync(".cancel.tmp", "utf8");
    writeFileSync(file, s);
    console.log("patched:", file);
  }
}

{
  const file = "src/lib/payments.ts";
  let s = readFileSync(file, "utf8");
  if (s.includes("./messaging")) {
    console.log("already patched:", file);
  } else {
    s = must(s, 'import { verifyTransaction } from "./paystack";', 'import { onBookingConfirmed } from "./messaging";\nimport { verifyTransaction } from "./paystack";', file);
    s = must(s, '    if (confirmed.length > 0) return "success";', '    if (confirmed.length > 0) {\n      await onBookingConfirmed(p.bookingId);\n      return "success";\n    }', file);
    writeFileSync(file, s);
    console.log("patched:", file);
  }
}
PATCH_EOF

node patch-sms.mjs
rm -f patch-sms.mjs .cancel.tmp

# ================= env =================
touch .env.local .env.example
grep -q '^SMS_DRY_RUN' .env.local || printf '\nSMS_DRY_RUN="true"\n' >> .env.local
grep -q '^ARKESEL_API_KEY' .env.local || printf 'ARKESEL_API_KEY="PASTE_YOUR_ARKESEL_KEY_HERE"\n' >> .env.local
grep -q '^SMS_SENDER_ID' .env.local || printf 'SMS_SENDER_ID="Bookings"\n' >> .env.local
if ! grep -q '^CRON_SECRET' .env.local; then
  printf 'CRON_SECRET="%s"\n' "$(node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")" >> .env.local
fi
for k in SMS_DRY_RUN ARKESEL_API_KEY SMS_SENDER_ID CRON_SECRET; do
  grep -q "^$k" .env.example || printf '%s=""\n' "$k" >> .env.example
done

# ================= migrate =================
npm run db:generate
npm run db:migrate

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
echo "SMS_DRY_RUN is on, so texts print in the dev server terminal and nothing is sent."
