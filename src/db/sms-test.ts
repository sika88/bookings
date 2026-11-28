import { sendSms } from "../lib/sms";

async function main() {
  const raw = (process.argv[2] ?? "").replace(/\D/g, "");
  if (raw.length < 9) {
    console.error("Usage: npm run db:sms:test -- 0241234567");
    process.exit(1);
  }
  const to = raw.startsWith("233") ? `+${raw}` : `+233${raw.replace(/^0/, "")}`;
  const r = await sendSms(to, "Test message from your booking app. If you got this, SMS is working.");
  console.log(r);
}
main();
