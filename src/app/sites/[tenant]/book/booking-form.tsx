"use client";

import { useActionState } from "react";
import { createBooking } from "../actions";
import type { BookingState } from "../types";

export default function BookingForm({
  slug,
  serviceId,
  staffId,
  start,
  label,
}: {
  slug: string;
  serviceId: string;
  staffId?: string;
  start: string;
  label: string;
}) {
  const [state, action, pending] = useActionState<BookingState, FormData>(createBooking, undefined);
  const v = state?.values;

  return (
    <form action={action} className="form">
      <input type="hidden" name="slug" value={slug} />
      <input type="hidden" name="serviceId" value={serviceId} />
      {staffId && <input type="hidden" name="staffId" value={staffId} />}
      <input type="hidden" name="start" value={start} />

      <label>
        Your name
        <input name="name" required autoComplete="name" defaultValue={v?.name} className="field" />
      </label>
      <label>
        Phone number
        <input name="phone" type="tel" required autoComplete="tel" placeholder="024 123 4567" defaultValue={v?.phone} className="field" />
      </label>
      <label>
        Email (optional)
        <input name="email" type="email" autoComplete="email" defaultValue={v?.email} className="field" />
      </label>
      <label>
        Notes (optional)
        <textarea name="notes" rows={2} defaultValue={v?.notes} className="field" />
      </label>
      <p className="muted small">We will text your confirmation and reminders to this number.</p>

      {state?.error && <p className="alert" role="alert">{state.error}</p>}
      <button disabled={pending} className="btn">
        {pending ? "Booking..." : label}
      </button>
    </form>
  );
}
