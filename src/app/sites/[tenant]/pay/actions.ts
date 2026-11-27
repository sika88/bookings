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
