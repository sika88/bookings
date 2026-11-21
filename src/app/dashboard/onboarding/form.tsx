"use client";

import { useActionState } from "react";
import { createTenant, type FormState } from "./actions";

export default function OnboardingForm({ rootDomain }: { rootDomain: string }) {
  const [state, action, pending] = useActionState<FormState, FormData>(createTenant, undefined);

  return (
    <form action={action} className="space-y-3">
      <input name="name" placeholder="Business name" required className="w-full rounded border p-2" />
      <div className="flex items-center gap-2">
        <input name="slug" placeholder="your-address" required className="w-full rounded border p-2" />
        <span className="whitespace-nowrap text-sm text-neutral-500">.{rootDomain}</span>
      </div>
      <select name="type" required defaultValue="salon" className="w-full rounded border p-2">
        <option value="salon">Salon</option>
        <option value="barber">Barber</option>
        <option value="clinic">Clinic</option>
        <option value="venue">Event space</option>
      </select>
      {state?.error && <p className="text-sm text-red-600">{state.error}</p>}
      <button disabled={pending} className="w-full rounded bg-black p-2 text-white disabled:opacity-50">
        {pending ? "Creating..." : "Create my booking page"}
      </button>
    </form>
  );
}
