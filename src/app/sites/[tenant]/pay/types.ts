export type PayState =
  | { step: "form"; error?: string }
  | { step: "otp"; reference: string; message: string }
  | { step: "waiting"; reference: string; message: string }
  | { step: "done" }
  | { step: "failed"; message: string };
