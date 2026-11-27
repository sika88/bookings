import type { Network } from "./networks";

const BASE = "https://api.paystack.co";

export type PaystackData = {
  id?: number;
  status?: string;
  reference?: string;
  amount?: number;
  currency?: string;
  channel?: string;
  display_text?: string;
  gateway_response?: string;
  message?: string;
};
export type PaystackReply = { status: boolean; message: string; data?: PaystackData };

export const paystackConfigured = () => !!process.env.PAYSTACK_SECRET_KEY && !process.env.PAYSTACK_SECRET_KEY.includes("PASTE_YOUR_KEY");

async function call(path: string, init?: { method?: string; body?: unknown }): Promise<PaystackReply> {
  const key = process.env.PAYSTACK_SECRET_KEY;
  if (!key) throw new Error("PAYSTACK_SECRET_KEY is not set");

  const res = await fetch(`${BASE}${path}`, {
    method: init?.method ?? "GET",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: init?.body ? JSON.stringify(init.body) : undefined,
    cache: "no-store",
    signal: AbortSignal.timeout(20_000),
  });

  const json = (await res.json().catch(() => null)) as PaystackReply | null;
  return json ?? { status: false, message: `Paystack returned HTTP ${res.status}` };
}

export function chargeMomo(a: {
  reference: string;
  email: string;
  amountPesewas: number;
  phone: string; // local format, 0241234567
  network: Network;
  metadata?: Record<string, string>;
}) {
  return call("/charge", {
    method: "POST",
    body: {
      email: a.email,
      amount: a.amountPesewas,
      currency: "GHS",
      reference: a.reference,
      mobile_money: { phone: a.phone, provider: a.network },
      metadata: a.metadata,
    },
  });
}

export const submitOtp = (reference: string, otp: string) =>
  call("/charge/submit_otp", { method: "POST", body: { otp, reference } });

export const verifyTransaction = (reference: string) => call(`/transaction/verify/${encodeURIComponent(reference)}`);
