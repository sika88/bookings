import type { ReactNode } from "react";
import type { bookings } from "@/db/schema";
import { statusHue } from "@/lib/css";
import { formatTime, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";

type Booking = typeof bookings.$inferSelect;

const STATUS: Record<string, { label: string; hue: number }> = {
  pending: { label: "Awaiting deposit", hue: 38 },
  confirmed: { label: "Confirmed", hue: 150 },
  completed: { label: "Completed", hue: 200 },
  cancelled: { label: "Cancelled", hue: 0 },
  no_show: { label: "No-show", hue: 20 },
};

export default function BookingCard({
  b,
  service,
  staffName,
  customer,
  phone,
  tz,
  showDate,
  actions,
}: {
  b: Booking;
  service: string;
  staffName: string;
  customer: string;
  phone: string;
  tz: string;
  showDate?: boolean;
  actions?: ReactNode;
}) {
  const st = STATUS[b.status] ?? { label: b.status, hue: 220 };

  return (
    <li className={`bk${b.status === "cancelled" ? " off" : ""}`}>
      <div className="bk-time">
        {formatTime(b.startsAt, tz)}
        <span className="muted small">{formatTime(b.endsAt, tz)}</span>
      </div>
      <div className="bk-main">
        <div className="item-title">{service}</div>
        {showDate && <div className="muted small">{formatWhen(b.startsAt, tz)}</div>}
        <div className="muted small">with {staffName}</div>
        <div className="small">
          {customer} <span className="muted">{phone}</span>
        </div>
        {b.notes && <div className="muted small">Note: {b.notes}</div>}
      </div>
      <div className="bk-side">
        <span className="status" style={statusHue(st.hue)}>{st.label}</span>
        <span className="muted small">
          {formatMoney(b.totalPesewas)}
          {b.depositPesewas > 0 ? `, deposit ${formatMoney(b.depositPesewas)}` : ""}
        </span>
      </div>
      {actions && <div className="bk-actions">{actions}</div>}
    </li>
  );
}
