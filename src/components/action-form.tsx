"use client";

import { useActionState } from "react";

export type ActionState = { error?: string; ok?: boolean } | undefined;

export default function ActionForm({
  action,
  submitLabel,
  children,
  className = "space-y-3",
}: {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  submitLabel: string;
  children: React.ReactNode;
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, undefined);

  return (
    <form action={formAction} className={className}>
      {children}
      {state?.error && <p className="text-sm text-red-600">{state.error}</p>}
      {state?.ok && <p className="text-sm text-green-700">Saved.</p>}
      <button disabled={pending} className="rounded bg-black px-4 py-2 text-sm text-white disabled:opacity-50">
        {pending ? "Saving..." : submitLabel}
      </button>
    </form>
  );
}
