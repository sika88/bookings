import { desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { tenantSlugHistory } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { publicUrl, requireTenant } from "@/lib/context";
import { num } from "@/lib/css";
import PageHead from "../page-head";
import { updateAddress, updateBusiness } from "./actions";

export default async function SettingsPage() {
  const { tenant, role } = await requireTenant();

  const [history, url, sample] = await Promise.all([
    db.select().from(tenantSlugHistory).where(eq(tenantSlugHistory.tenantId, tenant.id)).orderBy(desc(tenantSlugHistory.createdAt)),
    publicUrl(tenant.slug),
    publicUrl("SLUG"),
  ]);
  const [prefix, suffix] = sample.replace(/^https?:\/\//, "").split("SLUG");

  return (
    <>
      <PageHead title="Settings" sub="Your business details and booking page address." />

      <section className="glass panel enter" style={{ ...num(1), maxWidth: "44rem" }}>
        <h2 className="panel-title">Business</h2>
        <ActionForm action={updateBusiness} submitLabel="Save name">
          <label>
            Business name
            <input name="name" required defaultValue={tenant.name} className="field" />
          </label>
        </ActionForm>
      </section>

      <section className="glass panel enter" style={{ ...num(2), maxWidth: "44rem" }}>
        <h2 className="panel-title">Booking page address</h2>
        <p className="muted small" style={{ marginBottom: "1rem" }}>
          Customers book at{" "}
          <a href={url} target="_blank" rel="noreferrer" className="link">{url}</a>
        </p>

        {role === "owner" ? (
          <ActionForm action={updateAddress} submitLabel="Change address">
            <label>
              New address
              <div className="field-group">
                {prefix && <span className="suffix" style={{ paddingLeft: "0.95rem" }}>{prefix}</span>}
                <input name="slug" required defaultValue={tenant.slug} autoCapitalize="none" spellCheck={false} />
                {suffix && <span className="suffix">{suffix}</span>}
              </div>
            </label>
            <p className="muted small">
              Use 3 to 40 letters, numbers or single hyphens. Changing it is safe: your old address keeps working and redirects to the new one, so links you have already shared or texted still open the right page. Old addresses stay reserved for you.
            </p>
          </ActionForm>
        ) : (
          <p className="muted small">Only the owner can change the booking address.</p>
        )}

        {history.length > 0 && (
          <div style={{ marginTop: "1.5rem" }}>
            <div className="muted small" style={{ marginBottom: "0.5rem" }}>Old addresses (redirecting here)</div>
            <div className="pills">
              {history.map((h) => (
                <span key={h.id} className="pill">{h.slug}</span>
              ))}
            </div>
          </div>
        )}
      </section>
    </>
  );
}
