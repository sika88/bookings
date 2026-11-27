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
