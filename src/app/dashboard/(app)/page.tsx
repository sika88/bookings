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
