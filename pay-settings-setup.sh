#!/usr/bin/env bash
set -e

mkdir -p src/lib src/db/schema \
  "src/app/sites/[tenant]/pay" \
  "src/app/sites/[tenant]/booking/[token]" \
  src/app/api/paystack/webhook \
  "src/app/dashboard/(app)/settings" \
  "src/app/dashboard/(app)/bookings" \
  "src/app/dashboard/(auth)/onboarding"

# ================= database =================
cat > src/db/schema/payments.ts <<'EOF'
import { index, integer, jsonb, pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";
import { bookings } from "./booking";

export const paymentStatus = pgEnum("payment_status", ["pending", "success", "failed", "refund_due", "mismatch"]);

export const payments = pgTable(
  "payments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    bookingId: uuid("booking_id").notNull().references(() => bookings.id),
    reference: text("reference").notNull().unique(),
    amountPesewas: integer("amount_pesewas").notNull(),
    currency: text("currency").notNull().default("GHS"),
    network: text("network").notNull(),
    phone: text("phone").notNull(),
    status: paymentStatus("status").notNull().default("pending"),
    providerStatus: text("provider_status"),
    message: text("message"),
    raw: jsonb("raw"),
    lastCheckedAt: timestamp("last_checked_at", { withTimezone: true }),
    paidAt: timestamp("paid_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("payments_booking_idx").on(t.bookingId), index("payments_tenant_status_idx").on(t.tenantId, t.status)],
);
EOF

cat > src/db/schema/slug-history.ts <<'EOF'
import { index, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";

// Every address a business has used before. Kept so old links redirect and nobody else can take them.
export const tenantSlugHistory = pgTable(
  "tenant_slug_history",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    slug: text("slug").notNull().unique(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("slug_history_tenant_idx").on(t.tenantId)],
);
EOF

cat > src/db/schema/index.ts <<'EOF'
export * from "./tenants";
export * from "./auth";
export * from "./memberships";
export * from "./booking";
export * from "./payments";
export * from "./slug-history";
EOF

# ================= shared libs =================
cat > src/lib/reserved.ts <<'EOF'
// Addresses nobody can claim: they clash with our own routes, hosts or common sense.
export const RESERVED_SLUGS = new Set([
  "app", "www", "api", "admin", "dashboard", "sites", "static", "assets", "cdn", "mail", "email", "smtp", "ftp",
  "ns1", "ns2", "support", "help", "blog", "docs", "status", "billing", "pricing", "about", "contact", "terms",
  "privacy", "login", "signup", "register", "logout", "auth", "account", "accounts", "onboarding", "settings",
  "services", "staff", "bookings", "book", "booking", "b", "pay", "payments", "webhook", "webhooks", "paystack",
  "root", "test", "demo", "staging", "dev", "beta",
]);
EOF

cat > src/lib/slug.ts <<'EOF'
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { tenants, tenantSlugHistory } from "@/db/schema";
import { RESERVED_SLUGS } from "./reserved";

const FORMAT = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// Validates a booking-page address. Pass ownTenantId when an existing business is renaming.
export async function checkSlug(input: string, ownTenantId?: string): Promise<{ error: string } | { slug: string }> {
  const slug = input.trim().toLowerCase();

  if (slug.length < 3) return { error: "Address must be at least 3 characters" };
  if (slug.length > 40) return { error: "Address can be at most 40 characters" };
  if (!FORMAT.test(slug)) return { error: "Use only letters, numbers and single hyphens" };
  if (RESERVED_SLUGS.has(slug)) return { error: "That address is reserved" };

  const [current] = await db.select({ id: tenants.id }).from(tenants).where(eq(tenants.slug, slug)).limit(1);
  if (current) return { error: current.id === ownTenantId ? "That is already your address" : "That address is already taken" };

  // addresses other businesses used before stay reserved for them; your own old ones can be taken back
  const [old] = await db
    .select({ tenantId: tenantSlugHistory.tenantId })
    .from(tenantSlugHistory)
    .where(eq(tenantSlugHistory.slug, slug))
    .limit(1);
  if (old && old.tenantId !== ownTenantId) return { error: "That address is already taken" };

  return { slug };
}
EOF

cat > src/lib/networks.ts <<'EOF'
// Pure helpers, safe to import from client components.
export const NETWORKS = { mtn: "MTN MoMo", vod: "Telecel Cash", atl: "AirtelTigo Money" } as const;
export type Network = keyof typeof NETWORKS;

export const isNetwork = (s: string): s is Network => s === "mtn" || s === "vod" || s === "atl";

export function guessNetwork(input: string): Network | null {
  const d = input.replace(/\D/g, "").replace(/^233/, "0");
  const p = d.slice(0, 3);
  if (["024", "025", "053", "054", "055", "059"].includes(p)) return "mtn";
  if (["020", "050"].includes(p)) return "vod";
  if (["026", "027", "056", "057"].includes(p)) return "atl";
  return null;
}

// +233241234567 -> 0241234567
export const toLocalPhone = (e164: string) => `0${e164.replace(/\D/g, "").slice(-9)}`;
EOF

cat > src/lib/paystack.ts <<'EOF'
import type { Network } from "./networks";

const BASE = "https://api.paystack.co";

export type PaystackData = {
  id?: number;
  status?: string;
  reference?: string;
  amount?: number;
  currency?: string;
  channel?: string;
  display_text?: string;
  gateway_response?: string;
  message?: string;
};
export type PaystackReply = { status: boolean; message: string; data?: PaystackData };

export const paystackConfigured = () => !!process.env.PAYSTACK_SECRET_KEY && !process.env.PAYSTACK_SECRET_KEY.includes("PASTE_YOUR_KEY");

async function call(path: string, init?: { method?: string; body?: unknown }): Promise<PaystackReply> {
  const key = process.env.PAYSTACK_SECRET_KEY;
  if (!key) throw new Error("PAYSTACK_SECRET_KEY is not set");

  const res = await fetch(`${BASE}${path}`, {
    method: init?.method ?? "GET",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: init?.body ? JSON.stringify(init.body) : undefined,
    cache: "no-store",
    signal: AbortSignal.timeout(20_000),
  });

  const json = (await res.json().catch(() => null)) as PaystackReply | null;
  return json ?? { status: false, message: `Paystack returned HTTP ${res.status}` };
}

export function chargeMomo(a: {
  reference: string;
  email: string;
  amountPesewas: number;
  phone: string; // local format, 0241234567
  network: Network;
  metadata?: Record<string, string>;
}) {
  return call("/charge", {
    method: "POST",
    body: {
      email: a.email,
      amount: a.amountPesewas,
      currency: "GHS",
      reference: a.reference,
      mobile_money: { phone: a.phone, provider: a.network },
      metadata: a.metadata,
    },
  });
}

export const submitOtp = (reference: string, otp: string) =>
  call("/charge/submit_otp", { method: "POST", body: { otp, reference } });

export const verifyTransaction = (reference: string) => call(`/transaction/verify/${encodeURIComponent(reference)}`);
EOF

cat > src/lib/payments.ts <<'EOF'
import { and, eq, inArray, ne } from "drizzle-orm";
import { db } from "@/db";
import { bookings, payments } from "@/db/schema";
import { verifyTransaction } from "./paystack";

export type PayOutcome = "pending" | "success" | "failed" | "refund_due" | "mismatch" | "unknown";

const FAILED = new Set(["failed", "reversed", "timeout"]);

// Keep a pending booking's hold alive while the customer is paying.
export async function extendHold(bookingId: string, minutes: number) {
  const [b] = await db
    .select({ hold: bookings.holdExpiresAt, status: bookings.status })
    .from(bookings)
    .where(eq(bookings.id, bookingId))
    .limit(1);
  if (!b || b.status !== "pending") return;

  const target = Date.now() + minutes * 60_000;
  if (b.hold && b.hold.getTime() >= target) return;

  await db
    .update(bookings)
    .set({ holdExpiresAt: new Date(target) })
    .where(and(eq(bookings.id, bookingId), eq(bookings.status, "pending")));
}

// The one place a payment result is applied. Idempotent: the webhook, polling and retries can all call it.
export async function applyPaystackResult(d: {
  reference: string;
  status?: string;
  amount?: number;
  currency?: string;
  message?: string;
}): Promise<PayOutcome> {
  const [p] = await db.select().from(payments).where(eq(payments.reference, d.reference)).limit(1);
  if (!p) return "unknown";
  if (p.status === "success" || p.status === "refund_due" || p.status === "mismatch") return p.status;
  if (p.status === "failed" && d.status !== "success") return "failed";

  const flag = (message: string) =>
    db.update(payments).set({ status: "refund_due", message }).where(eq(payments.id, p.id));

  if (d.status === "success") {
    if (d.amount !== p.amountPesewas || (d.currency ?? p.currency) !== p.currency) {
      await db
        .update(payments)
        .set({ status: "mismatch", providerStatus: "success", message: "The amount paid did not match the deposit" })
        .where(eq(payments.id, p.id));
      return "mismatch";
    }

    const claimed = await db
      .update(payments)
      .set({ status: "success", providerStatus: "success", paidAt: new Date(), message: null })
      .where(and(eq(payments.id, p.id), inArray(payments.status, ["pending", "failed"])))
      .returning({ id: payments.id });
    if (claimed.length === 0) return "success"; // another request already handled it

    const confirmed = await db
      .update(bookings)
      .set({ status: "confirmed", holdExpiresAt: null })
      .where(and(eq(bookings.id, p.bookingId), eq(bookings.status, "pending")))
      .returning({ id: bookings.id });
    if (confirmed.length > 0) return "success";

    const [b] = await db.select({ status: bookings.status }).from(bookings).where(eq(bookings.id, p.bookingId)).limit(1);
    if (b?.status === "confirmed") {
      const [other] = await db
        .select({ id: payments.id })
        .from(payments)
        .where(and(eq(payments.bookingId, p.bookingId), eq(payments.status, "success"), ne(payments.id, p.id)))
        .limit(1);
      if (other) {
        await flag("Duplicate payment for a booking that was already paid");
        return "refund_due";
      }
      return "success";
    }

    // paid, but the booking was cancelled or its time was released: the money has to go back
    await flag("Paid after the booking was released");
    return "refund_due";
  }

  if (d.status && FAILED.has(d.status)) {
    await db
      .update(payments)
      .set({ status: "failed", providerStatus: d.status, message: d.message ?? "The payment was not completed" })
      .where(and(eq(payments.id, p.id), eq(payments.status, "pending")));
    return "failed";
  }

  return "pending";
}

// Asks Paystack for the current status (at most every 8 seconds) and applies it.
export async function syncPayment(reference: string): Promise<PayOutcome> {
  const [p] = await db.select().from(payments).where(eq(payments.reference, reference)).limit(1);
  if (!p) return "unknown";
  if (p.status !== "pending") return p.status;

  const now = Date.now();
  if (!p.lastCheckedAt || now - p.lastCheckedAt.getTime() >= 8000) {
    await db.update(payments).set({ lastCheckedAt: new Date() }).where(eq(payments.id, p.id));
    const res = await verifyTransaction(reference).catch(() => null);
    if (res?.status && res.data) {
      const outcome = await applyPaystackResult({
        reference,
        status: res.data.status,
        amount: res.data.amount,
        currency: res.data.currency,
        message: res.data.gateway_response,
      });
      if (outcome !== "pending") return outcome;
    }
  }

  // the customer has about 3 minutes to approve; a code step gets a little longer
  const limit = p.providerStatus === "send_otp" ? 300_000 : 195_000;
  if (now - p.createdAt.getTime() > limit) {
    await db
      .update(payments)
      .set({ status: "failed", message: "No approval was received in time. Please try again." })
      .where(and(eq(payments.id, p.id), eq(payments.status, "pending")));
    return "failed";
  }

  return "pending";
}
EOF

# old addresses redirect to the new one, keeping the path (so old booking links still work)
cat > src/lib/tenant.ts <<'EOF'
import { cache } from "react";
import { headers } from "next/headers";
import { permanentRedirect } from "next/navigation";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { tenants, tenantSlugHistory } from "@/db/schema";

async function renamedUrl(newSlug: string) {
  const h = await headers();
  const host = h.get("host") ?? "";
  const hostname = host.split(":")[0];
  const proto = h.get("x-forwarded-proto") ?? (hostname === "localhost" || hostname.endsWith(".localhost") ? "http" : "https");
  const orig = h.get("x-orig") ?? "/";
  const base = h.get("x-base") ?? "";

  if (/^\/b\/[a-z0-9-]+$/.test(base)) {
    const rest = orig.startsWith(base) ? orig.slice(base.length) : "";
    return `${proto}://${host}/b/${newSlug}${rest || "/"}`;
  }

  const rootFull = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
  return rootFull ? `${proto}://${newSlug}.${rootFull}${orig}` : null;
}

export const getTenantBySlug = cache(async (slug: string) => {
  const [tenant] = await db.select().from(tenants).where(eq(tenants.slug, slug)).limit(1);
  if (tenant) return tenant.status === "active" ? tenant : null;

  const [old] = await db
    .select({ slug: tenants.slug, status: tenants.status })
    .from(tenantSlugHistory)
    .innerJoin(tenants, eq(tenantSlugHistory.tenantId, tenants.id))
    .where(eq(tenantSlugHistory.slug, slug))
    .limit(1);

  if (old && old.status === "active") {
    const url = await renamedUrl(old.slug);
    if (url) permanentRedirect(url);
  }
  return null;
});
EOF

cat > src/proxy.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";

const ROOT_FULL = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
const ROOT = ROOT_FULL.split(":")[0];

export function proxy(req: NextRequest) {
  const hostname = (req.headers.get("host") ?? "").split(":")[0];
  const { pathname, search, protocol } = req.nextUrl;

  const sub = ROOT && hostname.endsWith(`.${ROOT}`) ? hostname.slice(0, -(ROOT.length + 1)) : null;

  // the bare domain (and www) lands on the app
  if (ROOT && (hostname === ROOT || sub === "www")) {
    return NextResponse.redirect(new URL(`${pathname}${search}`, `${protocol}//app.${ROOT_FULL}`));
  }

  // never let a client set our internal headers
  const fwd = new Headers(req.headers);
  fwd.delete("x-base");
  fwd.delete("x-orig");
  const orig = `${pathname}${search}`;

  // a business's public booking page on its own subdomain
  if (sub && sub !== "app") {
    fwd.set("x-orig", orig);
    const url = req.nextUrl.clone();
    url.pathname = `/sites/${sub}${pathname}`;
    return NextResponse.rewrite(url, { request: { headers: fwd } });
  }

  // path-based booking pages for hosts without tenant subdomains (e.g. *.vercel.app)
  const m = /^\/b\/([a-z0-9-]+)(\/.*)?$/.exec(pathname);
  if (m) {
    fwd.set("x-orig", orig);
    fwd.set("x-base", `/b/${m[1]}`);
    const url = req.nextUrl.clone();
    url.pathname = `/sites/${m[1]}${m[2] ?? ""}`;
    return NextResponse.rewrite(url, { request: { headers: fwd } });
  }

  // app.<root>, or any other host: the dashboard
  const url = req.nextUrl.clone();
  url.pathname = `/dashboard${pathname}`;
  return NextResponse.rewrite(url, { request: { headers: fwd } });
}

export const config = {
  matcher: ["/((?!api|_next|_static|.*\\..*).*)"],
};
EOF

# ================= payments: public side =================
cat > "src/app/sites/[tenant]/pay/types.ts" <<'EOF'
export type PayState =
  | { step: "form"; error?: string }
  | { step: "otp"; reference: string; message: string }
  | { step: "waiting"; reference: string; message: string }
  | { step: "done" }
  | { step: "failed"; message: string };
EOF

cat > "src/app/sites/[tenant]/pay/actions.ts" <<'EOF'
"use server";

import { and, desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, payments } from "@/db/schema";
import { normalizeGhPhone } from "@/lib/bookings";
import { isNetwork, toLocalPhone } from "@/lib/networks";
import { chargeMomo, paystackConfigured, submitOtp, type PaystackReply } from "@/lib/paystack";
import { extendHold, syncPayment, type PayOutcome } from "@/lib/payments";
import { getTenantBySlug } from "@/lib/tenant";
import type { PayState } from "./types";

const TOKEN = /^[a-f0-9]{32}$/;

async function loadBooking(slug: string, token: string) {
  if (!TOKEN.test(token)) return null;
  const tenant = await getTenantBySlug(slug);
  if (!tenant) return null;

  const [row] = await db
    .select({ b: bookings, email: customers.email })
    .from(bookings)
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .where(and(eq(bookings.manageToken, token), eq(bookings.tenantId, tenant.id)))
    .limit(1);
  return row ? { tenant, ...row } : null;
}

const markFailed = (id: string, message: string) =>
  db
    .update(payments)
    .set({ status: "failed", message })
    .where(and(eq(payments.id, id), eq(payments.status, "pending")));

// What to show after a charge or an OTP submission came back from Paystack.
async function settle(reply: PaystackReply, payId: string, reference: string): Promise<PayState> {
  const d = reply.data;
  if (!reply.status || !d) return { step: "form", error: reply.message || "The payment could not be started" };

  await db
    .update(payments)
    .set({ providerStatus: d.status ?? null, message: d.display_text ?? d.message ?? null, raw: d })
    .where(eq(payments.id, payId));

  switch (d.status) {
    case "success": {
      const outcome = await syncPayment(reference);
      if (outcome === "success") return { step: "done" };
      if (outcome === "refund_due") {
        return { step: "failed", message: "We received your payment, but this time was already released. The business will refund you." };
      }
      return { step: "waiting", reference, message: "Confirming your payment..." };
    }
    case "send_otp":
      return { step: "otp", reference, message: d.display_text ?? "Enter the code you were sent to continue." };
    case "failed": {
      const msg = d.message ?? d.gateway_response ?? "The payment was declined";
      await markFailed(payId, msg);
      return { step: "failed", message: msg };
    }
    default:
      return { step: "waiting", reference, message: d.display_text ?? "Approve the payment prompt on your phone." };
  }
}

export async function payAction(_prev: PayState, formData: FormData): Promise<PayState> {
  const intent = String(formData.get("intent") ?? "start");
  const found = await loadBooking(String(formData.get("slug") ?? ""), String(formData.get("token") ?? ""));
  if (!found) return { step: "failed", message: "We could not find this booking." };
  const { b, tenant, email } = found;

  if (b.status === "confirmed") return { step: "done" };
  if (!paystackConfigured()) return { step: "form", error: "Online payments are not set up yet. Please contact the business." };

  const now = Date.now();
  if (b.status !== "pending" || !b.holdExpiresAt || b.holdExpiresAt.getTime() <= now || b.depositPesewas <= 0) {
    return { step: "failed", message: "This hold has expired. Please book the time again." };
  }

  // the customer wants to start over (wrong number, wrong network)
  if (intent === "reset") {
    await db
      .update(payments)
      .set({ status: "failed", message: "Replaced by a new attempt" })
      .where(and(eq(payments.bookingId, b.id), eq(payments.status, "pending")));
    return { step: "form" };
  }

  if (intent === "otp") {
    const reference = String(formData.get("reference") ?? "");
    const otp = String(formData.get("otp") ?? "").trim();
    if (!/^[A-Za-z0-9]{3,12}$/.test(otp)) return { step: "otp", reference, message: "Enter the code you received." };

    const [pay] = await db
      .select()
      .from(payments)
      .where(and(eq(payments.reference, reference), eq(payments.bookingId, b.id), eq(payments.status, "pending")))
      .limit(1);
    if (!pay) return { step: "failed", message: "This payment is no longer active. Please try again." };

    await extendHold(b.id, 5);
    let reply: PaystackReply;
    try {
      reply = await submitOtp(reference, otp);
    } catch {
      return { step: "otp", reference, message: "We could not reach the payment provider. Please try again." };
    }
    if (!reply.status) return { step: "otp", reference, message: reply.message || "That code was not accepted. Try again." };
    return settle(reply, pay.id, reference);
  }

  // ----- start a new charge -----
  const network = String(formData.get("network") ?? "");
  const phone = normalizeGhPhone(String(formData.get("phone") ?? ""));
  if (!phone) return { step: "form", error: "Enter a valid Ghana mobile money number, like 024 123 4567" };
  if (!isNetwork(network)) return { step: "form", error: "Choose your mobile money network" };

  // never double-charge: reuse a prompt that is still live
  const [live] = await db
    .select()
    .from(payments)
    .where(and(eq(payments.bookingId, b.id), eq(payments.status, "pending")))
    .orderBy(desc(payments.createdAt))
    .limit(1);
  if (live && now - live.createdAt.getTime() < 180_000) {
    return {
      step: live.providerStatus === "send_otp" ? "otp" : "waiting",
      reference: live.reference,
      message: live.message ?? "Approve the payment prompt on your phone.",
    };
  }

  await extendHold(b.id, 5);

  const reference = `bk-${b.id.replaceAll("-", "")}-${Date.now().toString(36)}`;
  const [pay] = await db
    .insert(payments)
    .values({ tenantId: tenant.id, bookingId: b.id, reference, amountPesewas: b.depositPesewas, network, phone, status: "pending" })
    .returning({ id: payments.id });

  let reply: PaystackReply;
  try {
    reply = await chargeMomo({
      reference,
      email: email || `guest-${b.id.slice(0, 8)}@example.com`,
      amountPesewas: b.depositPesewas,
      phone: toLocalPhone(phone),
      network,
      metadata: { booking_id: b.id, tenant_id: tenant.id },
    });
  } catch {
    await markFailed(pay.id, "Could not reach the payment provider");
    return { step: "form", error: "We could not reach the payment provider. Please try again." };
  }

  if (!reply.status) await markFailed(pay.id, reply.message);
  return settle(reply, pay.id, reference);
}

// Called every few seconds while the customer approves the prompt.
export async function checkPayment(slug: string, token: string): Promise<{ outcome: PayOutcome | "none"; message?: string }> {
  const found = await loadBooking(slug, token);
  if (!found) return { outcome: "none" };

  const [p] = await db
    .select()
    .from(payments)
    .where(eq(payments.bookingId, found.b.id))
    .orderBy(desc(payments.createdAt))
    .limit(1);
  if (!p) return { outcome: "none" };

  const outcome = await syncPayment(p.reference);
  if (outcome === "failed" || outcome === "mismatch") {
    const [fresh] = await db.select({ message: payments.message }).from(payments).where(eq(payments.id, p.id)).limit(1);
    return { outcome, message: fresh?.message ?? undefined };
  }
  return { outcome };
}
EOF

cat > "src/app/sites/[tenant]/pay/pay-panel.tsx" <<'EOF'
"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { guessNetwork, NETWORKS, type Network } from "@/lib/networks";
import { checkPayment, payAction } from "./actions";
import type { PayState } from "./types";

export default function PayPanel({
  slug,
  token,
  amountLabel,
  defaultPhone,
  initial,
}: {
  slug: string;
  token: string;
  amountLabel: string;
  defaultPhone: string;
  initial: PayState;
}) {
  const router = useRouter();
  const [state, action, pending] = useActionState<PayState, FormData>(payAction, initial);
  const [local, setLocal] = useState<PayState>();
  const [phone, setPhone] = useState(defaultPhone);
  const [network, setNetwork] = useState<Network>(guessNetwork(defaultPhone) ?? "mtn");

  const view = local ?? state;
  const step = view.step;

  const submit = (fd: FormData) => {
    setLocal(undefined);
    action(fd);
  };

  useEffect(() => {
    if (step === "done") router.refresh();
  }, [step, router]);

  // while the customer approves on their phone, check for the result
  useEffect(() => {
    if (step !== "waiting") return;
    let live = true;
    const id = setInterval(async () => {
      const r = await checkPayment(slug, token);
      if (!live) return;
      if (r.outcome === "success" || r.outcome === "refund_due") {
        clearInterval(id);
        router.refresh();
      } else if (r.outcome === "failed" || r.outcome === "mismatch") {
        clearInterval(id);
        setLocal({ step: "failed", message: r.message ?? "The payment was not completed." });
      }
    }, 4000);
    return () => {
      live = false;
      clearInterval(id);
    };
  }, [step, slug, token, router]);

  const ids = (
    <>
      <input type="hidden" name="slug" value={slug} />
      <input type="hidden" name="token" value={token} />
    </>
  );

  if (view.step === "done") {
    return <p className="muted" role="status">Payment received. Confirming your booking...</p>;
  }

  if (view.step === "waiting") {
    return (
      <div className="wait" role="status" aria-live="polite">
        <span className="ring" aria-hidden="true" />
        <p className="display" style={{ fontSize: "1.25rem" }}>Waiting for your approval</p>
        <p className="muted">{view.message}</p>
        <p className="muted small">Approve the prompt and enter your PIN. This page updates by itself. You have about 3 minutes.</p>
        <form action={submit}>
          {ids}
          <input type="hidden" name="intent" value="reset" />
          <button className="linkbtn" disabled={pending}>Use a different number</button>
        </form>
      </div>
    );
  }

  if (view.step === "otp") {
    return (
      <form action={submit} className="form" style={{ marginTop: 0 }}>
        {ids}
        <input type="hidden" name="intent" value="otp" />
        <input type="hidden" name="reference" value={view.reference} />
        <p className="muted" role="status">{view.message}</p>
        <label>
          Code
          <input name="otp" required inputMode="numeric" autoComplete="one-time-code" className="field" />
        </label>
        <button disabled={pending} className="btn">{pending ? "Checking..." : "Confirm code"}</button>
      </form>
    );
  }

  if (view.step === "failed") {
    return (
      <div className="form" style={{ marginTop: 0 }}>
        <p className="alert" role="alert">{view.message}</p>
        <button type="button" className="btn" onClick={() => setLocal({ step: "form" })}>Try again</button>
      </div>
    );
  }

  return (
    <form action={submit} className="form" style={{ marginTop: 0 }}>
      {ids}
      <input type="hidden" name="intent" value="start" />
      <label>
        Mobile money number
        <input
          name="phone"
          type="tel"
          required
          autoComplete="tel"
          placeholder="024 123 4567"
          value={phone}
          onChange={(e) => {
            setPhone(e.target.value);
            const g = guessNetwork(e.target.value);
            if (g) setNetwork(g);
          }}
          className="field"
        />
      </label>
      <fieldset className="nets">
        <legend className="muted small" style={{ marginBottom: "0.5rem" }}>Network</legend>
        {(Object.keys(NETWORKS) as Network[]).map((code) => (
          <label key={code} className={`net${network === code ? " on" : ""}`}>
            <input type="radio" name="network" value={code} checked={network === code} onChange={() => setNetwork(code)} />
            {NETWORKS[code]}
          </label>
        ))}
      </fieldset>
      {view.error && <p className="alert" role="alert">{view.error}</p>}
      <button disabled={pending} className="btn">{pending ? "Sending prompt..." : `Pay ${amountLabel} with Mobile Money`}</button>
    </form>
  );
}
EOF

# ================= webhook =================
cat > src/app/api/paystack/webhook/route.ts <<'EOF'
import { createHmac, timingSafeEqual } from "node:crypto";
import { applyPaystackResult } from "@/lib/payments";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret) return new Response("not configured", { status: 500 });

  // the signature covers the exact raw body, so read it as text before parsing
  const raw = await req.text();
  const sent = Buffer.from(req.headers.get("x-paystack-signature") ?? "", "utf8");
  const expected = Buffer.from(createHmac("sha512", secret).update(raw).digest("hex"), "utf8");
  if (sent.length !== expected.length || !timingSafeEqual(sent, expected)) {
    return new Response("invalid signature", { status: 401 });
  }

  let evt: { event?: string; data?: { reference?: string; status?: string; amount?: number; currency?: string } };
  try {
    evt = JSON.parse(raw);
  } catch {
    return new Response("bad json", { status: 400 });
  }

  if (evt.event === "charge.success" && evt.data?.reference) {
    await applyPaystackResult({
      reference: evt.data.reference,
      status: evt.data.status,
      amount: evt.data.amount,
      currency: evt.data.currency,
    });
  }

  return new Response("ok", { status: 200 });
}
EOF

# ================= booking status page (adds the pay panel) =================
cat > "src/app/sites/[tenant]/booking/[token]/page.tsx" <<'EOF'
import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, payments, services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { basePath } from "@/lib/base";
import { HOLD_MINUTES } from "@/lib/bookings";
import { formatTime, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { toLocalPhone } from "@/lib/networks";
import { paystackConfigured } from "@/lib/paystack";
import { cancelBooking } from "../../actions";
import { Check, Clock, Cross } from "../../icons";
import PayPanel from "../../pay/pay-panel";
import type { PayState } from "../../pay/types";
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
      phone: customers.phone,
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

  const pays = await db.select().from(payments).where(eq(payments.bookingId, b.id)).orderBy(desc(payments.createdAt));
  const refundDue = pays.some((p) => p.status === "refund_due");
  const last = pays[0];

  let initial: PayState = { step: "form" };
  if (last?.status === "pending" && now - last.createdAt.getTime() < 195_000) {
    initial = {
      step: last.providerStatus === "send_otp" ? "otp" : "waiting",
      reference: last.reference,
      message: last.message ?? "Approve the payment prompt on your phone.",
    };
  }

  let title = "";
  let message = "";
  let hue = 0;
  let icon: "check" | "clock" | "cross" = "cross";

  if (b.status === "confirmed") {
    title = "You are booked";
    message = b.depositPesewas > 0 ? "Your deposit was received. Keep this page to check or cancel your booking." : "Keep this page. You can check or cancel your booking from it.";
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

      {refundDue && (
        <section className="glass panel enter" style={num(1)}>
          <p className="alert" role="status">
            We received a payment for this booking, but the time could not be confirmed. {tenant.name} will refund it to your mobile money wallet.
          </p>
        </section>
      )}

      {holdActive && (
        <section className="glass panel enter" style={num(1)}>
          <h2 className="display" style={{ fontSize: "1.3rem", marginBottom: "1rem" }}>
            Pay your {formatMoney(b.depositPesewas)} deposit
          </h2>
          {paystackConfigured() ? (
            <PayPanel
              slug={slug}
              token={token}
              amountLabel={formatMoney(b.depositPesewas)}
              defaultPhone={toLocalPhone(row.phone)}
              initial={initial}
            />
          ) : (
            <p className="muted">Online payment is not switched on for this business yet. Please contact them to pay your deposit.</p>
          )}
        </section>
      )}

      <section className="glass panel enter" style={num(2)}>
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

      <div className="enter" style={{ ...num(3), display: "grid", gap: "0.75rem" }}>
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
EOF

# ================= dashboard: settings =================
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
import { tenantSlugHistory } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { publicUrl, requireTenant } from "@/lib/context";
import { num } from "@/lib/css";
import PageHead from "../page-head";
import { updateAddress, updateBusiness } from "./actions";

export default async function SettingsPage() {
  const { tenant, role } = await requireTenant();

  const [history, url, sample] = await Promise.all([
    db.select().from(tenantSlugHistory).where(eq(tenantSlugHistory.tenantId, tenant.id)).orderBy(desc(tenantSlugHistory.createdAt)),
    publicUrl(tenant.slug),
    publicUrl("SLUG"),
  ]);
  const [prefix, suffix] = sample.replace(/^https?:\/\//, "").split("SLUG");

  return (
    <>
      <PageHead title="Settings" sub="Your business details and booking page address." />

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

if ! grep -q "export function Gear" src/components/icons.tsx; then
cat >> src/components/icons.tsx <<'EOF'
export function Gear() {
  return (
    <svg {...base}>
      <circle cx="8" cy="8" r="2.2" />
      <path d="M8 1.8v1.6M8 12.6v1.6M1.8 8h1.6M12.6 8h1.6M3.6 3.6l1.1 1.1M11.3 11.3l1.1 1.1M3.6 12.4l1.1-1.1M11.3 4.7l1.1-1.1" />
    </svg>
  );
}
EOF
fi

cat > "src/app/dashboard/(app)/nav.tsx" <<'EOF'
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Calendar, Gear, Grid, List, Users } from "@/components/icons";

const items = [
  { href: "/", label: "Overview", Icon: Grid },
  { href: "/bookings", label: "Bookings", Icon: Calendar },
  { href: "/services", label: "Services", Icon: List },
  { href: "/staff", label: "Staff", Icon: Users },
  { href: "/settings", label: "Settings", Icon: Gear },
];

export default function Nav() {
  const raw = usePathname();
  // the proxy rewrites app.* requests to /dashboard/*, so normalise both forms
  const path = raw.replace(/^\/dashboard(?=\/|$)/, "") || "/";

  return (
    <nav className="nav" aria-label="Dashboard">
      {items.map(({ href, label, Icon }) => {
        const active = href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`);
        return (
          <Link key={href} href={href} aria-current={active ? "page" : undefined} className={`nav-link${active ? " active" : ""}`}>
            <Icon />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
EOF

# onboarding now uses the shared address rules
cat > "src/app/dashboard/(auth)/onboarding/actions.ts" <<'EOF'
"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { pgCode } from "@/lib/bookings";
import { getSession } from "@/lib/session";
import { checkSlug } from "@/lib/slug";

const input = z.object({
  name: z.string().trim().min(2, "Business name is too short").max(80, "Business name is too long"),
  type: z.enum(["salon", "clinic", "barber", "venue"]),
});

export type FormState = { error?: string } | undefined;

export async function createTenant(_prev: FormState, formData: FormData): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");

  const parsed = input.safeParse({ name: formData.get("name"), type: formData.get("type") });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const slug = await checkSlug(String(formData.get("slug") ?? ""));
  if ("error" in slug) return { error: slug.error };

  const id = crypto.randomUUID();
  try {
    // batch = one atomic transaction over the neon-http driver
    await db.batch([
      db.insert(tenants).values({ id, slug: slug.slug, ...parsed.data }),
      db.insert(memberships).values({ tenantId: id, userId: session.user.id, role: "owner" }),
    ]);
  } catch (e) {
    if (pgCode(e) === "23505") return { error: "That address is already taken" };
    throw e;
  }
  redirect("/");
}
EOF

# ================= dashboard: bookings (adds the refunds panel) =================
cat > "src/app/dashboard/(app)/bookings/page.tsx" <<'EOF'
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
EOF

# ================= styles for the pay panel =================
if ! grep -q "pay-panel" src/styles/glass.css; then
cat >> src/styles/glass.css <<'EOF'

/* ---------- pay-panel ---------- */
.nets { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 0.5rem; border: 0; padding: 0; margin: 0; min-width: 0; }
.nets legend { grid-column: 1 / -1; padding: 0; }
.net {
  position: relative; display: grid; place-items: center; text-align: center; padding: 0.8rem 0.4rem; border-radius: 16px; font-size: 0.85rem; line-height: 1.2;
  background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line); cursor: pointer; transition: background 0.2s, border-color 0.2s, transform 0.2s;
}
.net:hover { background: rgba(255, 255, 255, 0.12); }
.net:active { transform: scale(0.97); }
.net input { position: absolute; inset: 0; width: 100%; height: 100%; margin: 0; opacity: 0; cursor: pointer; }
.net.on { background: hsl(var(--h) 95% 62% / 0.28); border-color: hsl(var(--h) 100% 78% / 0.7); }
.net:has(input:focus-visible) { outline: 2px solid var(--accent); outline-offset: 3px; }
.wait { display: grid; gap: 0.8rem; justify-items: center; text-align: center; padding: 0.5rem 0; }
.ring { width: 3.2rem; height: 3.2rem; border-radius: 50%; border: 3px solid rgba(255, 255, 255, 0.18); border-top-color: var(--accent); animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
.linkbtn { background: none; border: 0; padding: 0; color: var(--accent); text-decoration: underline; text-underline-offset: 3px; font: inherit; font-size: 0.9rem; cursor: pointer; }
.linkbtn:disabled { opacity: 0.5; cursor: not-allowed; }
EOF
fi

# ================= env =================
touch .env.local .env.example
grep -q '^PAYSTACK_SECRET_KEY' .env.local || printf '\nPAYSTACK_SECRET_KEY="sk_test_PASTE_YOUR_KEY_HERE"\n' >> .env.local
grep -q '^PAYSTACK_SECRET_KEY' .env.example || printf '\nPAYSTACK_SECRET_KEY=""\n' >> .env.example

# ================= migrate =================
npm run db:generate
npm run db:migrate

echo ""
if grep -q "PASTE_YOUR_KEY" .env.local; then
  echo "NEXT: put your Paystack TEST secret key in .env.local (PAYSTACK_SECRET_KEY), then restart the dev server."
else
  echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
fi
