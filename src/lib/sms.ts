import { toLocalPhone } from "./networks";

export type SmsResult = { ok: true; id?: string } | { ok: false; error: string; retryable: boolean };

const dryRun = () => process.env.SMS_DRY_RUN === "true";

export const smsConfigured = () =>
  dryRun() || (!!process.env.MNOTIFY_API_KEY && !process.env.MNOTIFY_API_KEY.includes("PASTE_YOUR"));

// to: +233XXXXXXXXX
export async function sendSms(to: string, message: string): Promise<SmsResult> {
  if (dryRun()) {
    console.log(`[sms dry run] to ${to}: ${message}`);
    return { ok: true, id: "dry-run" };
  }

  const key = process.env.MNOTIFY_API_KEY;
  const sender = process.env.SMS_SENDER_ID;
  if (!key || !sender) return { ok: false, error: "MNOTIFY_API_KEY or SMS_SENDER_ID is missing", retryable: false };

  try {
    // mNotify takes the key as a query parameter, so never log this URL
    const res = await fetch(`https://api.mnotify.com/api/sms/quick?key=${encodeURIComponent(key)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        recipient: [toLocalPhone(to)],
        sender,
        message,
      }),
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });

    const json = (await res.json().catch(() => null)) as
      | { status?: string; code?: string | number; message?: string; summary?: { _id?: string } }
      | null;

    if (res.ok && (json?.status === "success" || String(json?.code) === "2000")) {
      return { ok: true, id: json?.summary?._id };
    }
    return {
      ok: false,
      error: json?.message ?? `HTTP ${res.status}`,
      retryable: res.status >= 500 || res.status === 429,
    };
  } catch {
    return { ok: false, error: "Could not reach the SMS provider", retryable: true };
  }
}
