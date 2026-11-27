import { createHmac, timingSafeEqual } from "node:crypto";
import { applyPaystackResult } from "@/lib/payments";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret) return new Response("not configured", { status: 500 });

  // the signature covers the exact raw body, so read it as text before parsing
  const raw = await req.text();
  const sent = Buffer.from(req.headers.get("x-paystack-signature") ?? "", "utf8");
  const expected = Buffer.from(createHmac("sha512", secret).update(raw).digest("hex"), "utf8");
  if (sent.length !== expected.length || !timingSafeEqual(sent, expected)) {
    return new Response("invalid signature", { status: 401 });
  }

  let evt: { event?: string; data?: { reference?: string; status?: string; amount?: number; currency?: string } };
  try {
    evt = JSON.parse(raw);
  } catch {
    return new Response("bad json", { status: 400 });
  }

  if (evt.event === "charge.success" && evt.data?.reference) {
    await applyPaystackResult({
      reference: evt.data.reference,
      status: evt.data.status,
      amount: evt.data.amount,
      currency: evt.data.currency,
    });
  }

  return new Response("ok", { status: 200 });
}
