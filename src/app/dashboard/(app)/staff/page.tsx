import Link from "next/link";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { staff } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { requireTenant } from "@/lib/context";
import { hueVar, num } from "@/lib/css";
import { hueOf } from "@/lib/hue";
import PageHead from "../page-head";
import { createStaff } from "./actions";

export default async function StaffPage() {
  const { tenant } = await requireTenant();
  const rows = await db.select().from(staff).where(eq(staff.tenantId, tenant.id)).orderBy(asc(staff.displayName));

  return (
    <>
      <PageHead title="Staff" sub="The people customers can book with." />

      <div className="split">
        <section className="glass panel enter" style={num(1)}>
          {rows.length === 0 ? (
            <p className="muted empty-state">No staff yet. Add your first person with the form.</p>
          ) : (
            <ul className="list">
              {rows.map((s, i) => (
                <li key={s.id} className={`item pop${s.active ? "" : " off"}`} style={num(i)}>
                  <div className="item-lead">
                    <span className="avatar" style={hueVar(hueOf(s.displayName))}>{s.displayName.charAt(0).toUpperCase()}</span>
                    <div>
                      <div className="item-title">
                        {s.displayName}
                        {!s.active && <span className="pill">Hidden</span>}
                      </div>
                      {s.bio && <div className="muted small">{s.bio}</div>}
                    </div>
                  </div>
                  <Link href={`/staff/${s.id}`} className="act">Manage</Link>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="glass panel enter sticky" style={num(2)}>
          <h2 className="panel-title">Add a staff member</h2>
          <ActionForm action={createStaff} submitLabel="Add staff member">
            <label>
              Name
              <input name="displayName" required placeholder="Ama" className="field" />
            </label>
            <label>
              Short bio (optional)
              <input name="bio" className="field" />
            </label>
            <p className="muted small">
              New staff start with all your active services and Monday to Saturday, 09:00 to 18:00. You can change both on the next page.
            </p>
          </ActionForm>
        </section>
      </div>
    </>
  );
}
