import { desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, messages, tenantSlugHistory } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { publicUrl, requireTenant } from "@/lib/context";
import { num, statusHue } from "@/lib/css";
import { formatWhen } from "@/lib/format";
import PageHead from "../page-head";
import { updateAddress, updateBusiness, updateSms } from "./actions";

const KIND: Record<string, string> = {
  confirmation: "Confirmation",
  reminder_24h: "24-hour reminder",
  reminder_2h: "2-hour reminder",
  cancellation: "Cancellation notice",
};
const STATE: Record<string, { label: string; hue: number }> = {
  sent: { label: "Sent", hue: 150 },
  pending: { label: "Scheduled", hue: 38 },
  failed: { label: "Failed", hue: 0 },
  skipped: { label: "Skipped", hue: 220 },
};

export default async function SettingsPage() {
  const { tenant, role } = await requireTenant();

  const [history, recent, url, sample] = await Promise.all([
    db.select().from(tenantSlugHistory).where(eq(tenantSlugHistory.tenantId, tenant.id)).orderBy(desc(tenantSlugHistory.createdAt)),
    db
      .select({ m: messages, customer: customers.name })
      .from(messages)
      .innerJoin(bookings, eq(messages.bookingId, bookings.id))
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .where(eq(messages.tenantId, tenant.id))
      .orderBy(desc(messages.createdAt))
      .limit(8),
    publicUrl(tenant.slug),
    publicUrl("SLUG"),
  ]);
  const [prefix, suffix] = sample.replace(/^https?:\/\//, "").split("SLUG");

  return (
    <>
      <PageHead title="Settings" sub="Your business details, text messages and booking page address." />

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
        <h2 className="panel-title">Text messages</h2>
        <ActionForm action={updateSms} submitLabel="Save">
          <label className="switch">
            <input type="checkbox" name="smsEnabled" defaultChecked={tenant.smsEnabled} />
            <span className="track" aria-hidden="true" />
            Text customers about their bookings
          </label>
          <p className="muted small">
            Customers get a confirmation when their booking is confirmed, reminders 24 hours and 2 hours before, and a notice if it is cancelled.
          </p>
        </ActionForm>

        <div style={{ marginTop: "1.5rem" }}>
          <div className="muted small" style={{ marginBottom: "0.6rem" }}>Recent messages</div>
          {recent.length === 0 ? (
            <p className="muted small">Nothing sent yet. Messages appear here once customers book.</p>
          ) : (
            <ul className="list">
              {recent.map(({ m, customer }) => {
                const st = STATE[m.status] ?? { label: m.status, hue: 220 };
                return (
                  <li key={m.id} className="item">
                    <div>
                      <div className="item-title" style={{ fontSize: "1rem" }}>{KIND[m.kind] ?? m.kind}</div>
                      <div className="muted small">{customer}, {formatWhen(m.sentAt ?? m.sendAt, tenant.timezone)}</div>
                      {m.lastError && m.status !== "sent" && <div className="muted small">{m.lastError}</div>}
                    </div>
                    <span className="status" style={statusHue(st.hue)}>{st.label}</span>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>

      <section className="glass panel enter" style={{ ...num(3), maxWidth: "44rem" }}>
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
