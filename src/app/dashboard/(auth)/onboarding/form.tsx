"use client";

import { useActionState } from "react";
import { createTenant, type FormState } from "./actions";

export default function OnboardingForm({ rootDomain }: { rootDomain: string }) {
  const [state, action, pending] = useActionState<FormState, FormData>(createTenant, undefined);

  return (
    <form action={action} className="form">
      <label>
        Business name
        <input name="name" required placeholder="Glow Salon" className="field" />
      </label>
      <label>
        Your booking page address
        <div className="field-group">
          <input name="slug" required placeholder="glow-salon" autoCapitalize="none" />
          <span className="suffix">.{rootDomain}</span>
        </div>
      </label>
      <label>
        Type of business
        <select name="type" required defaultValue="salon" className="field">
          <option value="salon">Salon</option>
          <option value="barber">Barber</option>
          <option value="clinic">Clinic</option>
          <option value="venue">Event space</option>
        </select>
      </label>
      {state?.error && <p className="alert" role="alert">{state.error}</p>}
      <button disabled={pending} className="btn">{pending ? "Creating..." : "Create my booking page"}</button>
    </form>
  );
}
