#!/usr/bin/env bash
set -e

npm install drizzle-orm @neondatabase/serverless zod
npm install -D drizzle-kit dotenv tsx

npm pkg set scripts.db:generate="drizzle-kit generate"
npm pkg set scripts.db:migrate="drizzle-kit migrate"
npm pkg set scripts.db:studio="drizzle-kit studio"
npm pkg set scripts.db:seed="tsx --env-file=.env.local src/db/seed.ts"

if [ ! -f .env.local ]; then
  cat > .env.local <<'EOF'
DATABASE_URL="PASTE_POOLED_URL_HERE"
DATABASE_URL_UNPOOLED="PASTE_DIRECT_URL_HERE"
NEXT_PUBLIC_ROOT_DOMAIN="localhost:3000"
EOF
fi

cat > .env.example <<'EOF'
DATABASE_URL=""
DATABASE_URL_UNPOOLED=""
NEXT_PUBLIC_ROOT_DOMAIN="localhost:3000"
EOF

touch .gitignore
grep -q '^!\.env\.example' .gitignore || printf '\n!.env.example\n' >> .gitignore

mkdir -p src/db/schema src/lib "src/app/sites/[tenant]" src/app/dashboard

cat > drizzle.config.ts <<'EOF'
import { defineConfig } from "drizzle-kit";
import { config } from "dotenv";
config({ path: ".env.local" });

export default defineConfig({
  schema: "./src/db/schema/index.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL_UNPOOLED! },
});
EOF

cat > src/db/schema/tenants.ts <<'EOF'
import { pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

export const tenantType = pgEnum("tenant_type", ["salon", "clinic", "barber", "venue"]);

export const tenants = pgTable("tenants", {
  id: uuid("id").primaryKey().defaultRandom(),
  slug: text("slug").notNull().unique(),
  name: text("name").notNull(),
  type: tenantType("type").notNull(),
  timezone: text("timezone").notNull().default("Africa/Accra"),
  currency: text("currency").notNull().default("GHS"),
  status: text("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
EOF

echo 'export * from "./tenants";' > src/db/schema/index.ts

cat > src/db/index.ts <<'EOF'
import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import * as schema from "./schema";

export const db = drizzle(neon(process.env.DATABASE_URL!), { schema });
EOF

cat > src/db/seed.ts <<'EOF'
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
EOF

cat > src/lib/tenant.ts <<'EOF'
import { cache } from "react";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { tenants } from "@/db/schema";

export const getTenantBySlug = cache(async (slug: string) => {
  const [tenant] = await db.select().from(tenants).where(eq(tenants.slug, slug)).limit(1);
  return tenant && tenant.status === "active" ? tenant : null;
});
EOF

MAJOR=$(node -p "require('next/package.json').version.split('.')[0]")
if [ "$MAJOR" -ge 16 ]; then F=src/proxy.ts; FN=proxy; rm -f src/middleware.ts
else F=src/middleware.ts; FN=middleware; rm -f src/proxy.ts; fi

cat > "$F" <<'EOF'
import { NextRequest, NextResponse } from "next/server";

const ROOT = process.env.NEXT_PUBLIC_ROOT_DOMAIN!.split(":")[0];

export function __FN__(req: NextRequest) {
  const hostname = (req.headers.get("host") ?? "").split(":")[0];
  const sub = hostname.endsWith(`.${ROOT}`)
    ? hostname.slice(0, -(ROOT.length + 1))
    : null;

  if (!sub || sub === "www") return NextResponse.next();

  const url = req.nextUrl.clone();
  url.pathname =
    sub === "app" ? `/dashboard${url.pathname}` : `/sites/${sub}${url.pathname}`;
  return NextResponse.rewrite(url);
}

export const config = {
  matcher: ["/((?!api|_next|_static|.*\\..*).*)"],
};
EOF
sed -i.bak "s/__FN__/$FN/" "$F" && rm -f "$F.bak"

cat > "src/app/sites/[tenant]/page.tsx" <<'EOF'
import { notFound } from "next/navigation";
import { getTenantBySlug } from "@/lib/tenant";

export default async function TenantHome({
  params,
}: {
  params: Promise<{ tenant: string }>;
}) {
  const { tenant: slug } = await params;
  const tenant = await getTenantBySlug(slug);
  if (!tenant) notFound();

  return (
    <main className="mx-auto max-w-2xl p-8">
      <h1 className="text-3xl font-semibold">{tenant.name}</h1>
      <p className="text-neutral-500">Booking page coming soon.</p>
    </main>
  );
}
EOF

cat > src/app/dashboard/page.tsx <<'EOF'
export default function Dashboard() {
  return <main className="p-8">Tenant dashboard</main>;
}
EOF

if grep -q "PASTE_" .env.local; then
  echo ""
  echo "=============================================================="
  echo " Files created. Now open .env.local and paste your Neon URLs:"
  echo "   DATABASE_URL           -> pooled string (host has -pooler)"
  echo "   DATABASE_URL_UNPOOLED  -> direct string (no -pooler)"
  echo " Then run again:  bash setup.sh"
  echo "=============================================================="
  exit 0
fi

npm run db:generate
npm run db:migrate
npm run db:seed

echo ""
echo "Done. Start the app with:  npm run dev"
echo "Then open http://glow.localhost:3000"
