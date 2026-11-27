"use client";

import { useActionState } from "react";
import { Check } from "./icons";

export type ActionState = { error?: string; ok?: boolean } | undefined;

export default function ActionForm({
  action,
  submitLabel,
  children,
  className = "form flush",
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
      {state?.error && <p className="alert" role="alert">{state.error}</p>}
      <div className="form-foot">
        <button disabled={pending} className="btn btn-inline">
          {pending ? "Saving..." : submitLabel}
        </button>
        {state?.ok && (
          <span className="saved" role="status">
            <Check /> Saved
          </span>
        )}
      </div>
    </form>
  );
}
