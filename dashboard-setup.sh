#!/usr/bin/env bash
set -e

mkdir -p src/components src/lib \
  "src/app/dashboard/(app)/services/[id]" \
  "src/app/dashboard/(app)/staff/[id]"

# the old placeholder dashboard page is replaced by the (app) group below
rm -f src/app/dashboard/page.tsx

# ---------- shared helpers ----------
cat > src/lib/ids.ts <<'EOF'
export const isUuid = (s: string) =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
EOF

cat > src/lib/money.ts <<'EOF'
export const formatMoney = (pesewas: number) => `GH₵ ${(pesewas / 100).toFixed(2)}`;

export function depositLabel(type: string, value: number) {
  if (type === "fixed") return `${formatMoney(value)} deposit`;
  if (type === "percent") return `${value}% deposit`;
  return "No deposit";
}
EOF

cat > src/lib/context.ts <<'EOF'
import { cache } from "react";
import { redirect } from "next/navigation";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { getSession } from "./session";

// Resolves the signed-in user's business on the server. Never trust a tenant id from the client.
export const requireTenant = cache(async () => {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await db
    .select({ tenant: tenants, role: memberships.role })
    .from(memberships)
    .innerJoin(tenants, eq(memberships.tenantId, tenants.id))
    .where(eq(memberships.userId, session.user.id))
    .orderBy(asc(memberships.createdAt));

  if (rows.length === 0) redirect("/onboarding");
  return { session, tenant: rows[0].tenant, role: rows[0].role };
});

export const canManage = (role: string) => role === "owner" || role === "admin";

export function publicUrl(slug: string) {
  const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN!;
  const proto = process.env.NODE_ENV === "production" ? "https" : "http";
  return `${proto}://${slug}.${root}`;
}
EOF

cat > src/components/action-form.tsx <<'EOF'
"use client";

import { useActionState } from "react";

export type ActionState = { error?: string; ok?: boolean } | undefined;

export default function ActionForm({
  action,
  submitLabel,
  children,
  className = "space-y-3",
}: {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  submitLabel: string;
  children: React.ReactNode;
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, undefined);

  return (
    <form action={formAction} className={className}>
      {children}
      {state?.error && <p className="text-sm text-red-600">{state.error}</p>}
      {state?.ok && <p className="text-sm text-green-700">Saved.</p>}
      <button disabled={pending} className="rounded bg-black px-4 py-2 text-sm text-white disabled:opacity-50">
        {pending ? "Saving..." : submitLabel}
      </button>
    </form>
  );
}
EOF

# ---------- layout + overview ----------
cat > "src/app/dashboard/(app)/layout.tsx" <<'EOF'
import Link from "next/link";
import { publicUrl, requireTenant } from "@/lib/context";
import SignOutButton from "../sign-out-button";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { session, tenant } = await requireTenant();

  return (
    <div className="mx-auto max-w-3xl p-4 sm:p-8">
      <header className="mb-8 flex flex-wrap items-center justify-between gap-3 border-b pb-4">
        <div>
          <div className="font-semibold">{tenant.name}</div>
          <div className="text-xs text-neutral-500">{session.user.email}</div>
        </div>
        <nav className="flex flex-wrap items-center gap-4 text-sm">
          <Link href="/">Overview</Link>
          <Link href="/services">Services</Link>
          <Link href="/staff">Staff</Link>
          <a href={publicUrl(tenant.slug)} target="_blank" rel="noreferrer" className="underline">
            View booking page
          </a>
          <SignOutButton />
        </nav>
      </header>
      {children}
    </div>
  );
}
EOF

cat > "src/app/dashboard/(app)/page.tsx" <<'EOF'
import Link from "next/link";
import { and, count, eq } from "drizzle-orm";
import { db } from "@/db";
import { services, staff } from "@/db/schema";
import { publicUrl, requireTenant } from "@/lib/context";

export default async function Overview() {
  const { tenant } = await requireTenant();

  const [[svc], [stf]] = await Promise.all([
    db.select({ n: count() }).from(services).where(and(eq(services.tenantId, tenant.id), eq(services.active, true))),
    db.select({ n: count() }).from(staff).where(and(eq(staff.tenantId, tenant.id), eq(staff.active, true))),
  ]);

  const url = publicUrl(tenant.slug);
  const steps = [
    { done: svc.n > 0, label: "Add at least one service", href: "/services" },
    { done: stf.n > 0, label: "Add a staff member and set their working hours", href: "/staff" },
  ];

  return (
    <div className="space-y-8">
      <section>
        <h1 className="text-2xl font-semibold">Overview</h1>
        <p className="mt-2 text-sm text-neutral-500">Your public booking page:</p>
        <a href={url} target="_blank" rel="noreferrer" className="underline">{url}</a>
      </section>

      <section>
        <h2 className="mb-3 font-medium">Setup</h2>
        <ul className="space-y-2">
          {steps.map((s) => (
            <li key={s.href} className="flex items-center gap-3 rounded border p-3 text-sm">
              <span className={s.done ? "text-green-700" : "text-neutral-400"}>{s.done ? "✓" : "○"}</span>
              <Link href={s.href} className={s.done ? "text-neutral-500 line-through" : "underline"}>{s.label}</Link>
            </li>
          ))}
        </ul>
        <p className="mt-3 text-sm text-neutral-500">
          {svc.n} active service{svc.n === 1 ? "" : "s"} · {stf.n} active staff
        </p>
      </section>
    </div>
  );
}
EOF

# ---------- services ----------
cat > "src/app/dashboard/(app)/services/input.ts" <<'EOF'
import { z } from "zod";

const MONEY = /^\d+(\.\d{1,2})?$/;

const schema = z.object({
  name: z.string().trim().min(1, "Service name is required").max(80, "Name is too long"),
  description: z.string().trim().max(300, "Description is too long").optional(),
  durationMin: z.coerce.number().int("Duration must be a whole number").min(5, "Duration must be at least 5 minutes").max(720, "Duration is too long"),
  bufferMin: z.coerce.number().int("Buffer must be a whole number").min(0, "Buffer can't be negative").max(120, "Buffer is too long"),
  price: z.string().trim().regex(MONEY, "Enter a price like 50 or 50.00"),
  depositType: z.enum(["none", "fixed", "percent"]),
  deposit: z.string().trim().optional(),
});

export type ServiceInput = {
  name: string;
  description: string | null;
  durationMin: number;
  bufferMin: number;
  pricePesewas: number;
  depositType: "none" | "fixed" | "percent";
  depositValue: number;
};

export function parseService(formData: FormData): { error: string } | { data: ServiceInput } {
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const pricePesewas = Math.round(parseFloat(v.price) * 100);
  let depositValue = 0;

  if (v.depositType === "fixed") {
    if (!v.deposit || !MONEY.test(v.deposit)) return { error: "Enter the deposit amount, like 10 or 10.00" };
    depositValue = Math.round(parseFloat(v.deposit) * 100);
    if (depositValue <= 0) return { error: "The deposit must be more than 0" };
    if (depositValue > pricePesewas) return { error: "The deposit can't be more than the price" };
  } else if (v.depositType === "percent") {
    const n = Number(v.deposit);
    if (!Number.isInteger(n) || n < 1 || n > 100) return { error: "Deposit percentage must be a whole number from 1 to 100" };
    depositValue = n;
  }

  return {
    data: {
      name: v.name,
      description: v.description ? v.description : null,
      durationMin: v.durationMin,
      bufferMin: v.bufferMin,
      pricePesewas,
      depositType: v.depositType,
      depositValue,
    },
  };
}
EOF

cat > "src/app/dashboard/(app)/services/actions.ts" <<'EOF'
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
EOF

cat > "src/app/dashboard/(app)/services/fields.tsx" <<'EOF'
import type { services } from "@/db/schema";

type Svc = typeof services.$inferSelect;

const box = "mt-1 w-full rounded border p-2";

export default function ServiceFields({ service }: { service?: Svc }) {
  const depositDefault = !service
    ? ""
    : service.depositType === "fixed"
      ? (service.depositValue / 100).toFixed(2)
      : service.depositType === "percent"
        ? String(service.depositValue)
        : "";

  return (
    <>
      {service && <input type="hidden" name="id" value={service.id} />}

      <label className="block text-sm">
        Name
        <input name="name" required defaultValue={service?.name} placeholder="Haircut" className={box} />
      </label>

      <label className="block text-sm">
        Description (optional)
        <textarea name="description" rows={2} defaultValue={service?.description ?? ""} className={box} />
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className="block text-sm">
          Duration (minutes)
          <input name="durationMin" type="number" min={5} step={5} required defaultValue={service?.durationMin ?? 30} className={box} />
        </label>
        <label className="block text-sm">
          Buffer after (minutes)
          <input name="bufferMin" type="number" min={0} step={5} required defaultValue={service?.bufferMin ?? 0} className={box} />
        </label>
      </div>

      <label className="block text-sm">
        Price (GH₵)
        <input
          name="price"
          inputMode="decimal"
          required
          placeholder="50.00"
          defaultValue={service ? (service.pricePesewas / 100).toFixed(2) : ""}
          className={box}
        />
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className="block text-sm">
          Deposit
          <select name="depositType" defaultValue={service?.depositType ?? "none"} className={box}>
            <option value="none">No deposit</option>
            <option value="fixed">Fixed amount (GH₵)</option>
            <option value="percent">Percentage of price (%)</option>
          </select>
        </label>
        <label className="block text-sm">
          Deposit value
          <input name="deposit" inputMode="decimal" defaultValue={depositDefault} placeholder="10.00 or 30" className={box} />
        </label>
      </div>
      <p className="text-xs text-neutral-500">
        Deposit value is an amount in GH₵ for a fixed deposit, or a number from 1 to 100 for a percentage. Ignored when there is no deposit.
      </p>
    </>
  );
}
EOF

cat > "src/app/dashboard/(app)/services/page.tsx" <<'EOF'
import Link from "next/link";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { depositLabel, formatMoney } from "@/lib/money";
import ActionForm from "@/components/action-form";
import { createService, setServiceActive } from "./actions";
import ServiceFields from "./fields";

export default async function ServicesPage() {
  const { tenant } = await requireTenant();
  const rows = await db
    .select()
    .from(services)
    .where(eq(services.tenantId, tenant.id))
    .orderBy(asc(services.name));

  return (
    <div className="space-y-10">
      <section>
        <h1 className="mb-4 text-2xl font-semibold">Services</h1>
        {rows.length === 0 && <p className="text-sm text-neutral-500">No services yet. Add your first one below.</p>}
        <ul className="space-y-2">
          {rows.map((s) => (
            <li key={s.id} className="flex items-center justify-between gap-3 rounded border p-4">
              <div className={s.active ? "" : "opacity-50"}>
                <div className="font-medium">
                  {s.name}
                  {!s.active && <span className="ml-2 text-xs text-neutral-500">(hidden)</span>}
                </div>
                <div className="text-sm text-neutral-500">
                  {s.durationMin} min · {formatMoney(s.pricePesewas)} · {depositLabel(s.depositType, s.depositValue)}
                </div>
              </div>
              <div className="flex items-center gap-3 text-sm">
                <Link href={`/services/${s.id}`} className="underline">Edit</Link>
                <form action={setServiceActive}>
                  <input type="hidden" name="id" value={s.id} />
                  <input type="hidden" name="active" value={s.active ? "false" : "true"} />
                  <button className="underline">{s.active ? "Hide" : "Show"}</button>
                </form>
              </div>
            </li>
          ))}
        </ul>
        <p className="mt-3 text-xs text-neutral-500">
          Services can be hidden but not deleted, so past bookings keep their history.
        </p>
      </section>

      <section>
        <h2 className="mb-3 text-lg font-medium">Add a service</h2>
        <ActionForm action={createService} submitLabel="Add service">
          <ServiceFields />
        </ActionForm>
      </section>
    </div>
  );
}
EOF

cat > "src/app/dashboard/(app)/services/[id]/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import ActionForm from "@/components/action-form";
import { updateService } from "../actions";
import ServiceFields from "../fields";

export default async function EditService({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { tenant } = await requireTenant();
  if (!isUuid(id)) notFound();

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, id), eq(services.tenantId, tenant.id)))
    .limit(1);
  if (!service) notFound();

  return (
    <div className="space-y-6">
      <Link href="/services" className="text-sm underline">← Back to services</Link>
      <h1 className="text-2xl font-semibold">Edit service</h1>
      <ActionForm action={updateService} submitLabel="Save changes">
        <ServiceFields service={service} />
      </ActionForm>
    </div>
  );
}
EOF

# ---------- staff ----------
cat > "src/app/dashboard/(app)/staff/days.ts" <<'EOF'
// weekday numbers match the database: 0 = Sunday ... 6 = Saturday
export const DAYS = [
  { weekday: 1, label: "Monday" },
  { weekday: 2, label: "Tuesday" },
  { weekday: 3, label: "Wednesday" },
  { weekday: 4, label: "Thursday" },
  { weekday: 5, label: "Friday" },
  { weekday: 6, label: "Saturday" },
  { weekday: 0, label: "Sunday" },
];
EOF

cat > "src/app/dashboard/(app)/staff/actions.ts" <<'EOF'
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
EOF

cat > "src/app/dashboard/(app)/staff/page.tsx" <<'EOF'
import Link from "next/link";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { staff } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import ActionForm from "@/components/action-form";
import { createStaff } from "./actions";

export default async function StaffPage() {
  const { tenant } = await requireTenant();
  const rows = await db
    .select()
    .from(staff)
    .where(eq(staff.tenantId, tenant.id))
    .orderBy(asc(staff.displayName));

  return (
    <div className="space-y-10">
      <section>
        <h1 className="mb-4 text-2xl font-semibold">Staff</h1>
        {rows.length === 0 && <p className="text-sm text-neutral-500">No staff yet. Add your first person below.</p>}
        <ul className="space-y-2">
          {rows.map((s) => (
            <li key={s.id} className="flex items-center justify-between gap-3 rounded border p-4">
              <div className={s.active ? "" : "opacity-50"}>
                <div className="font-medium">
                  {s.displayName}
                  {!s.active && <span className="ml-2 text-xs text-neutral-500">(hidden)</span>}
                </div>
                {s.bio && <div className="text-sm text-neutral-500">{s.bio}</div>}
              </div>
              <Link href={`/staff/${s.id}`} className="text-sm underline">Manage</Link>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-3 text-lg font-medium">Add a staff member</h2>
        <ActionForm action={createStaff} submitLabel="Add staff member">
          <label className="block text-sm">
            Name
            <input name="displayName" required placeholder="Ama" className="mt-1 w-full rounded border p-2" />
          </label>
          <label className="block text-sm">
            Short bio (optional)
            <input name="bio" className="mt-1 w-full rounded border p-2" />
          </label>
          <p className="text-xs text-neutral-500">
            New staff start with all your active services and Monday to Saturday, 09:00 to 18:00. You can change both on the next page.
          </p>
        </ActionForm>
      </section>
    </div>
  );
}
EOF

cat > "src/app/dashboard/(app)/staff/[id]/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { availabilityRules, services, staff, staffServices } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import ActionForm from "@/components/action-form";
import { saveHours, updateStaff } from "../actions";
import { DAYS } from "../days";

const box = "mt-1 w-full rounded border p-2";

export default async function StaffDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { tenant } = await requireTenant();
  if (!isUuid(id)) notFound();

  const [member] = await db
    .select()
    .from(staff)
    .where(and(eq(staff.id, id), eq(staff.tenantId, tenant.id)))
    .limit(1);
  if (!member) notFound();

  const [allServices, linked, rules] = await Promise.all([
    db.select().from(services).where(eq(services.tenantId, tenant.id)).orderBy(asc(services.name)),
    db.select({ serviceId: staffServices.serviceId }).from(staffServices).where(eq(staffServices.staffId, member.id)),
    db
      .select()
      .from(availabilityRules)
      .where(and(eq(availabilityRules.staffId, member.id), eq(availabilityRules.tenantId, tenant.id))),
  ]);

  const linkedIds = new Set(linked.map((l) => l.serviceId));

  const byDay = new Map<number, { s: string; e: string }[]>();
  for (const r of [...rules].sort((a, b) => a.startTime.localeCompare(b.startTime))) {
    const list = byDay.get(r.weekday) ?? [];
    list.push({ s: r.startTime.slice(0, 5), e: r.endTime.slice(0, 5) });
    byDay.set(r.weekday, list);
  }

  return (
    <div className="space-y-10">
      <div>
        <Link href="/staff" className="text-sm underline">← Back to staff</Link>
        <h1 className="mt-3 text-2xl font-semibold">{member.displayName}</h1>
      </div>

      <section>
        <h2 className="mb-3 text-lg font-medium">Profile and services</h2>
        <ActionForm action={updateStaff} submitLabel="Save profile">
          <input type="hidden" name="id" value={member.id} />
          <label className="block text-sm">
            Name
            <input name="displayName" required defaultValue={member.displayName} className={box} />
          </label>
          <label className="block text-sm">
            Short bio (optional)
            <input name="bio" defaultValue={member.bio ?? ""} className={box} />
          </label>

          <fieldset className="space-y-2">
            <legend className="text-sm">Services this person offers</legend>
            {allServices.length === 0 && (
              <p className="text-sm text-neutral-500">
                No services yet. <Link href="/services" className="underline">Add a service</Link> first.
              </p>
            )}
            {allServices.map((s) => (
              <label key={s.id} className="flex items-center gap-2 text-sm">
                <input type="checkbox" name="serviceId" value={s.id} defaultChecked={linkedIds.has(s.id)} />
                {s.name}
                {!s.active && <span className="text-xs text-neutral-500">(hidden)</span>}
              </label>
            ))}
          </fieldset>

          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="active" defaultChecked={member.active} />
            Show on the booking page
          </label>
          <p className="text-xs text-neutral-500">Unticking hides this person from new bookings. Existing bookings are kept.</p>
        </ActionForm>
      </section>

      <section>
        <h2 className="mb-1 text-lg font-medium">Working hours</h2>
        <p className="mb-3 text-sm text-neutral-500">
          Leave a day empty for a day off. Use the second range for a break, for example 09:00 to 13:00, then 14:00 to 18:00.
        </p>
        <ActionForm action={saveHours} submitLabel="Save hours">
          <input type="hidden" name="id" value={member.id} />
          <div>
            {DAYS.map(({ weekday, label }) => {
              const ranges = byDay.get(weekday) ?? [];
              return (
                <div key={weekday} className="grid grid-cols-1 items-center gap-2 border-b py-2 sm:grid-cols-[7rem_1fr_1fr]">
                  <span className="text-sm font-medium">{label}</span>
                  {[1, 2].map((n) => (
                    <div key={n} className="flex items-center gap-1">
                      <input type="time" name={`d${weekday}_s${n}`} defaultValue={ranges[n - 1]?.s ?? ""} className="rounded border p-1 text-sm" />
                      <span className="text-neutral-400">to</span>
                      <input type="time" name={`d${weekday}_e${n}`} defaultValue={ranges[n - 1]?.e ?? ""} className="rounded border p-1 text-sm" />
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        </ActionForm>
      </section>
    </div>
  );
}
EOF

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
echo "Then open http://app.localhost:3000"
