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
