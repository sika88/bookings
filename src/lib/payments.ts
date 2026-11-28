import { and, eq, inArray, ne } from "drizzle-orm";
import { db } from "@/db";
import { bookings, payments } from "@/db/schema";
import { onBookingConfirmed } from "./messaging";
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
    if (confirmed.length > 0) {
      await onBookingConfirmed(p.bookingId);
      return "success";
    }

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
