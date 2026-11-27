import Link from "next/link";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { requireTenant } from "@/lib/context";
import { num } from "@/lib/css";
import { formatMoney } from "@/lib/money";
import PageHead from "../page-head";
import { createService, setServiceActive } from "./actions";
import ServiceFields from "./fields";

export default async function ServicesPage() {
  const { tenant } = await requireTenant();
  const rows = await db.select().from(services).where(eq(services.tenantId, tenant.id)).orderBy(asc(services.name));

  return (
    <>
      <PageHead title="Services" sub="What your customers can book, and what it costs." />

      <div className="split">
        <section className="glass panel enter" style={num(1)}>
          {rows.length === 0 ? (
            <p className="muted empty-state">No services yet. Add your first one with the form.</p>
          ) : (
            <ul className="list">
              {rows.map((s, i) => (
                <li key={s.id} className={`item pop${s.active ? "" : " off"}`} style={num(i)}>
                  <div>
                    <div className="item-title">
                      {s.name}
                      {!s.active && <span className="pill">Hidden</span>}
                    </div>
                    {s.description && <div className="muted small">{s.description}</div>}
                    <div className="pills">
                      <span className="pill">{s.durationMin} min</span>
                      <span className="pill">{formatMoney(s.pricePesewas)}</span>
                      {s.depositType !== "none" && (
                        <span className="pill accent">
                          {s.depositType === "fixed" ? `${formatMoney(s.depositValue)} deposit` : `${s.depositValue}% deposit`}
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="item-actions">
                    <Link href={`/services/${s.id}`} className="act">Edit</Link>
                    <form action={setServiceActive}>
                      <input type="hidden" name="id" value={s.id} />
                      <input type="hidden" name="active" value={s.active ? "false" : "true"} />
                      <button className="act">{s.active ? "Hide" : "Show"}</button>
                    </form>
                  </div>
                </li>
              ))}
            </ul>
          )}
          {rows.length > 0 && (
            <p className="muted small" style={{ marginTop: "1rem" }}>
              Services can be hidden but not deleted, so past bookings keep their history.
            </p>
          )}
        </section>

        <section className="glass panel enter sticky" style={num(2)}>
          <h2 className="panel-title">Add a service</h2>
          <ActionForm action={createService} submitLabel="Add service">
            <ServiceFields />
          </ActionForm>
        </section>
      </div>
    </>
  );
}
