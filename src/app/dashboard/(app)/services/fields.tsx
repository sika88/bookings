import type { services } from "@/db/schema";

type Svc = typeof services.$inferSelect;

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

      <label>
        Name
        <input name="name" required defaultValue={service?.name} placeholder="Haircut" className="field" />
      </label>

      <label>
        Description (optional)
        <textarea name="description" rows={2} defaultValue={service?.description ?? ""} className="field" />
      </label>

      <div className="two">
        <label>
          Duration (minutes)
          <input name="durationMin" type="number" min={5} step={5} required defaultValue={service?.durationMin ?? 30} className="field" />
        </label>
        <label>
          Buffer after (minutes)
          <input name="bufferMin" type="number" min={0} step={5} required defaultValue={service?.bufferMin ?? 0} className="field" />
        </label>
      </div>

      <label>
        Price (GH₵)
        <input
          name="price"
          inputMode="decimal"
          required
          placeholder="50.00"
          defaultValue={service ? (service.pricePesewas / 100).toFixed(2) : ""}
          className="field"
        />
      </label>

      <div className="two">
        <label>
          Deposit
          <select name="depositType" defaultValue={service?.depositType ?? "none"} className="field">
            <option value="none">No deposit</option>
            <option value="fixed">Fixed amount (GH₵)</option>
            <option value="percent">Percentage of price</option>
          </select>
        </label>
        <label>
          Deposit value
          <input name="deposit" inputMode="decimal" defaultValue={depositDefault} placeholder="10.00 or 30" className="field" />
        </label>
      </div>
      <p className="muted small">
        Enter an amount in GH₵ for a fixed deposit, or a number from 1 to 100 for a percentage. It is ignored when there is no deposit.
      </p>
    </>
  );
}
