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
