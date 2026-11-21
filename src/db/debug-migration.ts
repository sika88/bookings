import { neon } from "@neondatabase/serverless";
import { readdirSync, readFileSync } from "node:fs";

async function main() {
  const sql: any = neon(process.env.DATABASE_URL_UNPOOLED!);
  const run = (q: string) => (typeof sql.query === "function" ? sql.query(q) : sql(q));

  const files = readdirSync("drizzle").filter((f) => /^000[23]_.*\.sql$/.test(f)).sort();
  console.log("Testing:", files.join(", "));

  let failed = false;
  outer: for (const f of files) {
    const stmts = readFileSync(`drizzle/${f}`, "utf8")
      .split("--> statement-breakpoint")
      .map((s) => s.trim())
      .filter(Boolean);
    for (const [i, s] of stmts.entries()) {
      try {
        await run(s);
      } catch (e: any) {
        failed = true;
        console.log(`\nFAILED in ${f}, statement ${i + 1}:\n${s.slice(0, 400)}\n\nERROR: ${e.message}`);
        break outer;
      }
    }
    console.log(`OK: ${f} (${stmts.length} statements)`);
  }

  // always undo, so drizzle-kit can apply these migrations cleanly afterwards
  await run(`DROP TABLE IF EXISTS bookings, customers, time_off, availability_rules, staff_services, services, staff CASCADE`);
  await run(`DROP TYPE IF EXISTS booking_status`);
  await run(`DROP TYPE IF EXISTS deposit_type`);
  console.log(failed ? "\nRolled back test objects." : "\nAll statements ran OK; test objects removed again.");
}
main();
