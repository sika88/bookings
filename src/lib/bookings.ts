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
