import { neon } from "@neondatabase/serverless";

async function main() {
  const sql = neon(process.env.DATABASE_URL_UNPOOLED!);
  const [v] = await sql`select version() as v`;
  console.log("POSTGRES:", v.v);
  const tables = await sql`select table_name from information_schema.tables where table_schema = 'public' order by 1`;
  console.log("TABLES:", tables.map((t) => t.table_name).join(", "));
  try {
    const m = await sql`select id, created_at from drizzle.__drizzle_migrations order by id`;
    console.log("MIGRATIONS APPLIED:", m.length);
  } catch {
    console.log("MIGRATIONS APPLIED: could not read migrations table");
  }
}
main();
