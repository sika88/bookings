import { db } from "./index";
import { tenants } from "./schema";

async function main() {
  await db
    .insert(tenants)
    .values([
      { slug: "glow", name: "Glow Salon", type: "salon" },
      { slug: "sharp", name: "Sharp Cuts Barbers", type: "barber" },
    ])
    .onConflictDoNothing();
  console.log("seeded");
}
main();
