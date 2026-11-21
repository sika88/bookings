#!/usr/bin/env bash
set -e

npm install better-auth

# ---------- env ----------
SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")
grep -q '^BETTER_AUTH_SECRET' .env.local || printf '\nBETTER_AUTH_SECRET="%s"\nBETTER_AUTH_URL="http://app.localhost:3000"\n' "$SECRET" >> .env.local
grep -q '^BETTER_AUTH_SECRET' .env.example || printf '\nBETTER_AUTH_SECRET=""\nBETTER_AUTH_URL="http://app.localhost:3000"\n' >> .env.example

mkdir -p src/lib src/db/schema src/app/api/auth/\[...all\] \
  src/app/dashboard/login src/app/dashboard/signup src/app/dashboard/onboarding

# ---------- schema: Better Auth tables ----------
cat > src/db/schema/auth.ts <<'EOF'
import { boolean, pgTable, text, timestamp } from "drizzle-orm/pg-core";

const ts = (name: string) => timestamp(name, { withTimezone: true });

export const user = pgTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: boolean("email_verified").notNull().default(false),
  image: text("image"),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

export const session = pgTable("session", {
  id: text("id").primaryKey(),
  expiresAt: ts("expires_at").notNull(),
  token: text("token").notNull().unique(),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
});

export const account = pgTable("account", {
  id: text("id").primaryKey(),
  accountId: text("account_id").notNull(),
  providerId: text("provider_id").notNull(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  accessToken: text("access_token"),
  refreshToken: text("refresh_token"),
  idToken: text("id_token"),
  accessTokenExpiresAt: ts("access_token_expires_at"),
  refreshTokenExpiresAt: ts("refresh_token_expires_at"),
  scope: text("scope"),
  password: text("password"),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

export const verification = pgTable("verification", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: ts("expires_at").notNull(),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});
EOF

# ---------- schema: memberships ----------
cat > src/db/schema/memberships.ts <<'EOF'
import { pgEnum, pgTable, text, timestamp, unique, uuid } from "drizzle-orm/pg-core";
import { tenants } from "./tenants";
import { user } from "./auth";

export const memberRole = pgEnum("member_role", ["owner", "admin", "staff"]);

export const memberships = pgTable(
  "memberships",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    tenantId: uuid("tenant_id").notNull().references(() => tenants.id, { onDelete: "cascade" }),
    userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
    role: memberRole("role").notNull().default("staff"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [unique().on(t.tenantId, t.userId)],
);
EOF

cat > src/db/schema/index.ts <<'EOF'
export * from "./tenants";
export * from "./auth";
export * from "./memberships";
EOF

# ---------- auth core ----------
cat > src/lib/auth.ts <<'EOF'
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { nextCookies } from "better-auth/next-js";
import { db } from "../db";
import * as schema from "../db/schema";

const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN!;
const proto = process.env.NODE_ENV === "production" ? "https" : "http";

export const auth = betterAuth({
  database: drizzleAdapter(db, { provider: "pg", schema }),
  emailAndPassword: { enabled: true },
  trustedOrigins: [`${proto}://${root}`, `${proto}://app.${root}`],
  plugins: [nextCookies()],
});
EOF

cat > src/lib/auth-client.ts <<'EOF'
import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient();
EOF

cat > src/lib/session.ts <<'EOF'
import { headers } from "next/headers";
import { auth } from "./auth";

export async function getSession() {
  return auth.api.getSession({ headers: await headers() });
}
EOF

cat > "src/app/api/auth/[...all]/route.ts" <<'EOF'
import { auth } from "@/lib/auth";
import { toNextJsHandler } from "better-auth/next-js";

export const { GET, POST } = toNextJsHandler(auth);
EOF

# ---------- pages ----------
cat > src/app/dashboard/signup/page.tsx <<'EOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { authClient } from "@/lib/auth-client";

export default function SignUp() {
  const router = useRouter();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setError(undefined);
    const f = new FormData(e.currentTarget);
    const { error } = await authClient.signUp.email({
      name: String(f.get("name")),
      email: String(f.get("email")),
      password: String(f.get("password")),
    });
    if (error) {
      setError(error.message ?? "Could not create account");
      setLoading(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <main className="mx-auto max-w-sm p-8">
      <h1 className="mb-6 text-2xl font-semibold">Create your account</h1>
      <form onSubmit={onSubmit} className="space-y-3">
        <input name="name" placeholder="Your name" required className="w-full rounded border p-2" />
        <input name="email" type="email" placeholder="Email" required className="w-full rounded border p-2" />
        <input name="password" type="password" placeholder="Password (8+ characters)" minLength={8} required className="w-full rounded border p-2" />
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button disabled={loading} className="w-full rounded bg-black p-2 text-white disabled:opacity-50">
          {loading ? "Creating..." : "Sign up"}
        </button>
      </form>
      <p className="mt-4 text-sm">Have an account? <Link href="/login" className="underline">Log in</Link></p>
    </main>
  );
}
EOF

cat > src/app/dashboard/login/page.tsx <<'EOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { authClient } from "@/lib/auth-client";

export default function Login() {
  const router = useRouter();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setError(undefined);
    const f = new FormData(e.currentTarget);
    const { error } = await authClient.signIn.email({
      email: String(f.get("email")),
      password: String(f.get("password")),
    });
    if (error) {
      setError(error.message ?? "Invalid email or password");
      setLoading(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <main className="mx-auto max-w-sm p-8">
      <h1 className="mb-6 text-2xl font-semibold">Log in</h1>
      <form onSubmit={onSubmit} className="space-y-3">
        <input name="email" type="email" placeholder="Email" required className="w-full rounded border p-2" />
        <input name="password" type="password" placeholder="Password" required className="w-full rounded border p-2" />
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button disabled={loading} className="w-full rounded bg-black p-2 text-white disabled:opacity-50">
          {loading ? "Logging in..." : "Log in"}
        </button>
      </form>
      <p className="mt-4 text-sm">New here? <Link href="/signup" className="underline">Create an account</Link></p>
    </main>
  );
}
EOF

cat > src/app/dashboard/sign-out-button.tsx <<'EOF'
"use client";

import { useRouter } from "next/navigation";
import { authClient } from "@/lib/auth-client";

export default function SignOutButton() {
  const router = useRouter();
  return (
    <button
      className="rounded border px-3 py-1 text-sm"
      onClick={async () => {
        await authClient.signOut();
        router.push("/login");
        router.refresh();
      }}
    >
      Sign out
    </button>
  );
}
EOF

cat > src/app/dashboard/onboarding/actions.ts <<'EOF'
"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { getSession } from "@/lib/session";

const RESERVED = ["app", "www", "api", "admin", "dashboard", "sites", "static", "mail", "support", "help", "blog"];

const input = z.object({
  name: z.string().trim().min(2, "Business name is too short").max(80),
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .min(3, "Address must be at least 3 characters")
    .max(40)
    .regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, "Use only letters, numbers and single hyphens"),
  type: z.enum(["salon", "clinic", "barber", "venue"]),
});

export type FormState = { error?: string } | undefined;

export async function createTenant(_prev: FormState, formData: FormData): Promise<FormState> {
  const session = await getSession();
  if (!session) redirect("/login");

  const parsed = input.safeParse({
    name: formData.get("name"),
    slug: formData.get("slug"),
    type: formData.get("type"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  if (RESERVED.includes(parsed.data.slug)) return { error: "That address is reserved" };

  const id = crypto.randomUUID();
  try {
    // batch = one atomic transaction over the neon-http driver
    await db.batch([
      db.insert(tenants).values({ id, ...parsed.data }),
      db.insert(memberships).values({ tenantId: id, userId: session.user.id, role: "owner" }),
    ]);
  } catch {
    return { error: "That address is already taken" };
  }
  redirect("/");
}
EOF

cat > src/app/dashboard/onboarding/form.tsx <<'EOF'
"use client";

import { useActionState } from "react";
import { createTenant, type FormState } from "./actions";

export default function OnboardingForm({ rootDomain }: { rootDomain: string }) {
  const [state, action, pending] = useActionState<FormState, FormData>(createTenant, undefined);

  return (
    <form action={action} className="space-y-3">
      <input name="name" placeholder="Business name" required className="w-full rounded border p-2" />
      <div className="flex items-center gap-2">
        <input name="slug" placeholder="your-address" required className="w-full rounded border p-2" />
        <span className="whitespace-nowrap text-sm text-neutral-500">.{rootDomain}</span>
      </div>
      <select name="type" required defaultValue="salon" className="w-full rounded border p-2">
        <option value="salon">Salon</option>
        <option value="barber">Barber</option>
        <option value="clinic">Clinic</option>
        <option value="venue">Event space</option>
      </select>
      {state?.error && <p className="text-sm text-red-600">{state.error}</p>}
      <button disabled={pending} className="w-full rounded bg-black p-2 text-white disabled:opacity-50">
        {pending ? "Creating..." : "Create my booking page"}
      </button>
    </form>
  );
}
EOF

cat > src/app/dashboard/onboarding/page.tsx <<'EOF'
import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import OnboardingForm from "./form";

export default async function Onboarding() {
  const session = await getSession();
  if (!session) redirect("/login");

  return (
    <main className="mx-auto max-w-md p-8">
      <h1 className="mb-1 text-2xl font-semibold">Set up your business</h1>
      <p className="mb-6 text-sm text-neutral-500">This creates your public booking page.</p>
      <OnboardingForm rootDomain={process.env.NEXT_PUBLIC_ROOT_DOMAIN!} />
    </main>
  );
}
EOF

cat > src/app/dashboard/page.tsx <<'EOF'
import { redirect } from "next/navigation";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { getSession } from "@/lib/session";
import SignOutButton from "./sign-out-button";

export default async function Dashboard() {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await db
    .select({ tenant: tenants, role: memberships.role })
    .from(memberships)
    .innerJoin(tenants, eq(memberships.tenantId, tenants.id))
    .where(eq(memberships.userId, session.user.id));

  if (rows.length === 0) redirect("/onboarding");

  const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN!;
  const proto = process.env.NODE_ENV === "production" ? "https" : "http";

  return (
    <main className="mx-auto max-w-2xl p-8">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <SignOutButton />
      </div>
      <p className="mb-4 text-sm text-neutral-500">Signed in as {session.user.email}</p>
      <ul className="space-y-3">
        {rows.map(({ tenant, role }) => (
          <li key={tenant.id} className="rounded border p-4">
            <div className="font-medium">{tenant.name} <span className="text-xs text-neutral-500">({role})</span></div>
            <a className="text-sm underline" href={`${proto}://${tenant.slug}.${root}`} target="_blank">
              {tenant.slug}.{root}
            </a>
          </li>
        ))}
      </ul>
    </main>
  );
}
EOF

# ---------- database ----------
npm run db:generate
npm run db:migrate

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
echo "Then open http://app.localhost:3000"
