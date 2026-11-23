"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { and, eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db";
import { availabilityRules, services, staff, staffServices } from "@/db/schema";
import { canManage, requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import type { ActionState } from "@/components/action-form";
import { DAYS } from "./days";

const FORBIDDEN = "You don't have permission to do this";
const NOT_FOUND = "Staff member not found";

const profile = z.object({
  displayName: z.string().trim().min(1, "Name is required").max(60, "Name is too long"),
  bio: z.string().trim().max(300, "Bio is too long").optional(),
});

export async function createStaff(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: FORBIDDEN };

  const parsed = profile.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const id = crypto.randomUUID();

  // New staff start with every active service and Mon-Sat 09:00-18:00, editable on the next page.
  const activeServices = await db
    .select({ id: services.id })
    .from(services)
    .where(and(eq(services.tenantId, tenant.id), eq(services.active, true)));

  const insertStaff = db.insert(staff).values({
    id,
    tenantId: tenant.id,
    displayName: parsed.data.displayName,
    bio: parsed.data.bio ? parsed.data.bio : null,
  });
  const insertRules = db.insert(availabilityRules).values(
    [1, 2, 3, 4, 5, 6].map((weekday) => ({
      tenantId: tenant.id,
      staffId: id,
      weekday,
      startTime: "09:00",
      endTime: "18:00",
    })),
  );

  if (activeServices.length > 0) {
    await db.batch([
      insertStaff,
      db.insert(staffServices).values(activeServices.map((s) => ({ staffId: id, serviceId: s.id }))),
      insertRules,
    ]);
  } else {
    await db.batch([insertStaff, insertRules]);
  }

  revalidatePath("/dashboard", "layout");
  redirect(`/staff/${id}`);
}

export async function updateStaff(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: FORBIDDEN };

  const id = String(formData.get("id") ?? "");
  if (!isUuid(id)) return { error: NOT_FOUND };

  const parsed = profile.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const [updated] = await db
    .update(staff)
    .set({
      displayName: parsed.data.displayName,
      bio: parsed.data.bio ? parsed.data.bio : null,
      active: formData.get("active") === "on",
    })
    .where(and(eq(staff.id, id), eq(staff.tenantId, tenant.id)))
    .returning({ id: staff.id });
  if (!updated) return { error: NOT_FOUND };

  // only keep service ids that really belong to this business
  const wanted = formData.getAll("serviceId").map(String).filter(isUuid);
  let valid: string[] = [];
  if (wanted.length > 0) {
    const found = await db
      .select({ id: services.id })
      .from(services)
      .where(and(eq(services.tenantId, tenant.id), inArray(services.id, wanted)));
    valid = found.map((f) => f.id);
  }

  const clear = db.delete(staffServices).where(eq(staffServices.staffId, id));
  if (valid.length > 0) {
    await db.batch([clear, db.insert(staffServices).values(valid.map((serviceId) => ({ staffId: id, serviceId })))]);
  } else {
    await clear;
  }

  revalidatePath("/dashboard", "layout");
  return { ok: true };
}

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

export async function saveHours(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const { tenant, role } = await requireTenant();
  if (!canManage(role)) return { error: FORBIDDEN };

  const id = String(formData.get("id") ?? "");
  if (!isUuid(id)) return { error: NOT_FOUND };

  const [member] = await db
    .select({ id: staff.id })
    .from(staff)
    .where(and(eq(staff.id, id), eq(staff.tenantId, tenant.id)))
    .limit(1);
  if (!member) return { error: NOT_FOUND };

  const rows: { tenantId: string; staffId: string; weekday: number; startTime: string; endTime: string }[] = [];

  for (const { weekday, label } of DAYS) {
    const ranges: [string, string][] = [];

    for (const n of [1, 2]) {
      const s = String(formData.get(`d${weekday}_s${n}`) ?? "").trim();
      const e = String(formData.get(`d${weekday}_e${n}`) ?? "").trim();
      if (!s && !e) continue;
      if (!s || !e) return { error: `${label}: fill in both the start and the end time` };
      if (!TIME.test(s) || !TIME.test(e)) return { error: `${label}: use a valid time` };
      if (s >= e) return { error: `${label}: the end time must be after the start time` };
      ranges.push([s, e]);
    }

    ranges.sort((a, b) => a[0].localeCompare(b[0]));
    for (let i = 1; i < ranges.length; i++) {
      if (ranges[i][0] < ranges[i - 1][1]) return { error: `${label}: the two time ranges overlap` };
    }
    for (const [s, e] of ranges) {
      rows.push({ tenantId: tenant.id, staffId: id, weekday, startTime: s, endTime: e });
    }
  }

  const clear = db
    .delete(availabilityRules)
    .where(and(eq(availabilityRules.staffId, id), eq(availabilityRules.tenantId, tenant.id)));

  if (rows.length > 0) {
    await db.batch([clear, db.insert(availabilityRules).values(rows)]);
  } else {
    await clear;
  }

  revalidatePath("/dashboard", "layout");
  return { ok: true };
}
