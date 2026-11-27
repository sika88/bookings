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
