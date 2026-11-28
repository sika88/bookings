import { eq } from "drizzle-orm";
import { db } from "./index";
import { messages } from "./schema";

async function main() {
  const rows = await db
    .update(messages)
    .set({ sendAt: new Date(), claimedAt: null })
    .where(eq(messages.status, "pending"))
    .returning({ id: messages.id });
  console.log(`Moved ${rows.length} pending message(s) to now. Call the cron URL to send them.`);
}
main();
