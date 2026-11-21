import { neon } from "@neondatabase/serverless";

async function main() {
  const sql: any = neon(process.env.DATABASE_URL_UNPOOLED!);
  const run = (q: string) => (typeof sql.query === "function" ? sql.query(q) : sql(q));
  const show = async (label: string, q: string) => {
    try {
      const r = await run(q);
      console.log(label, Array.isArray(r) && r.length ? JSON.stringify(r) : "ok");
    } catch (e: any) {
      console.log(label, "ERROR:", e.message);
    }
  };

  await show("installed extensions:", `select e.extname, e.extversion, n.nspname as schema from pg_extension e join pg_namespace n on n.oid = e.extnamespace`);
  await show("btree_gist available:", `select name, default_version, installed_version from pg_available_extensions where name = 'btree_gist'`);
  await show("uuid opclasses before:", `select opcname from pg_opclass where opcname like 'gist_uuid%'`);
  await show("create extension:", `CREATE EXTENSION IF NOT EXISTS btree_gist`);
  await show("update extension:", `ALTER EXTENSION btree_gist UPDATE`);
  await show("uuid opclasses after:", `select opcname from pg_opclass where opcname like 'gist_uuid%'`);

  await run(`DROP TABLE IF EXISTS _gist_test`);
  await show("create test table:", `CREATE TABLE _gist_test (staff_id uuid, s timestamptz, e timestamptz)`);
  await show("A) uuid constraint:", `ALTER TABLE _gist_test ADD CONSTRAINT a EXCLUDE USING gist (staff_id WITH =, tstzrange(s, e) WITH &&)`);
  await show("B) text-cast constraint:", `ALTER TABLE _gist_test ADD CONSTRAINT b EXCLUDE USING gist ((staff_id::text) WITH =, tstzrange(s, e) WITH &&)`);
  await run(`DROP TABLE IF EXISTS _gist_test`);
  console.log("done, test table removed");
}
main();
