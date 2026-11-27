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
