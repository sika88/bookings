"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import { canManage, requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import type { ActionState } from "@/components/action-form";
import { parseService } from "./input";

const FORBIDDEN = "You don't have permission to do this";

export async function createService(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: FORBIDDEN };

  const r = parseService(formData);
  if ("error" in r) return { error: r.error };

  await db.insert(services).values({ tenantId: tenant.id, ...r.data });
  revalidatePath("/dashboard", "layout");
  redirect("/services");
}

export async function updateService(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: FORBIDDEN };

  const id = String(formData.get("id") ?? "");
  if (!isUuid(id)) return { error: "Service not found" };

  const r = parseService(formData);
  if ("error" in r) return { error: r.error };

  const updated = await db
    .update(services)
    .set(r.data)
    .where(and(eq(services.id, id), eq(services.tenantId, tenant.id)))
    .returning({ id: services.id });
  if (updated.length === 0) return { error: "Service not found" };

  revalidatePath("/dashboard", "layout");
  return { ok: true };
}

export async function setServiceActive(formData: FormData): Promise<void> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return;

  const id = String(formData.get("id") ?? "");
  if (!isUuid(id)) return;

  await db
    .update(services)
    .set({ active: formData.get("active") === "true" })
    .where(and(eq(services.id, id), eq(services.tenantId, tenant.id)));
  revalidatePath("/dashboard", "layout");
}
