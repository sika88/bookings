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
