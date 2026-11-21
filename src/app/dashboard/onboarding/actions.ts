"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { getSession } from "@/lib/session";

const RESERVED = ["app", "www", "api", "admin", "dashboard", "sites", "static", "mail", "support", "help", "blog"];

const input = z.object({
  name: z.string().trim().min(2, "Business name is too short").max(80),
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .min(3, "Address must be at least 3 characters")
    .max(40)
    .regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, "Use only letters, numbers and single hyphens"),
  type: z.enum(["salon", "clinic", "barber", "venue"]),
});

export type FormState = { error?: string } | undefined;

export async function createTenant(_prev: FormState, formData: FormData): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");

  const parsed = input.safeParse({
    name: formData.get("name"),
    slug: formData.get("slug"),
    type: formData.get("type"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  if (RESERVED.includes(parsed.data.slug)) return { error: "That address is reserved" };

  const id = crypto.randomUUID();
  try {
    // batch = one atomic transaction over the neon-http driver
    await db.batch([
      db.insert(tenants).values({ id, ...parsed.data }),
      db.insert(memberships).values({ tenantId: id, userId: session.user.id, role: "owner" }),
    ]);
  } catch {
    return { error: "That address is already taken" };
  }
  redirect("/");
}
