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
