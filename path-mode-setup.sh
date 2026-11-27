#!/usr/bin/env bash
set -e

# ---------- proxy: add /b/<slug> path mode, strip spoofable header ----------
cat > src/proxy.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";

const ROOT_FULL = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
const ROOT = ROOT_FULL.split(":")[0];

export function proxy(req: NextRequest) {
  const hostname = (req.headers.get("host") ?? "").split(":")[0];
  const { pathname, search, protocol } = req.nextUrl;

  const sub = ROOT && hostname.endsWith(`.${ROOT}`) ? hostname.slice(0, -(ROOT.length + 1)) : null;

  // the bare domain (and www) lands on the app
  if (ROOT && (hostname === ROOT || sub === "www")) {
    return NextResponse.redirect(new URL(`${pathname}${search}`, `${protocol}//app.${ROOT_FULL}`));
  }

  // never let a client set our internal header
  const fwd = new Headers(req.headers);
  fwd.delete("x-base");

  // a business's public booking page on its own subdomain
  if (sub && sub !== "app") {
    const url = req.nextUrl.clone();
    url.pathname = `/sites/${sub}${pathname}`;
    return NextResponse.rewrite(url, { request: { headers: fwd } });
  }

  // path-based booking pages for hosts without tenant subdomains (e.g. *.vercel.app)
  const m = /^\/b\/([a-z0-9-]+)(\/.*)?$/.exec(pathname);
  if (m) {
    const url = req.nextUrl.clone();
    url.pathname = `/sites/${m[1]}${m[2] ?? ""}`;
    fwd.set("x-base", `/b/${m[1]}`);
    return NextResponse.rewrite(url, { request: { headers: fwd } });
  }

  // app.<root>, or any other host: the dashboard
  const url = req.nextUrl.clone();
  url.pathname = `/dashboard${pathname}`;
  return NextResponse.rewrite(url, { request: { headers: fwd } });
}

export const config = {
  matcher: ["/((?!api|_next|_static|.*\\..*).*)"],
};
EOF

# ---------- helpers ----------
cat > src/lib/base.ts <<'EOF'
import { headers } from "next/headers";

// "" on a tenant subdomain, "/b/<slug>" when served in path mode.
export async function basePath() {
  const v = (await headers()).get("x-base") ?? "";
  return /^\/b\/[a-z0-9-]+$/.test(v) ? v : "";
}
EOF

cat > src/lib/context.ts <<'EOF'
import { cache } from "react";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { memberships, tenants } from "@/db/schema";
import { getSession } from "./session";

// Resolves the signed-in user's business on the server. Never trust a tenant id from the client.
export const requireTenant = cache(async () => {
  const session = await getSession();
  if (!session) redirect("/login");

  const rows = await db
    .select({ tenant: tenants, role: memberships.role })
    .from(memberships)
    .innerJoin(tenants, eq(memberships.tenantId, tenants.id))
    .where(eq(memberships.userId, session.user.id))
    .orderBy(asc(memberships.createdAt));

  if (rows.length === 0) redirect("/onboarding");
  return { session, tenant: rows[0].tenant, role: rows[0].role };
});

export const canManage = (role: string) => role === "owner" || role === "admin";

// Subdomain link when the current host sits under the root domain, otherwise a /b/<slug> path on this host.
export async function publicUrl(slug: string) {
  const h = await headers();
  const host = h.get("host") ?? "";
  const hostname = host.split(":")[0];
  const rootFull = process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "";
  const root = rootFull.split(":")[0];
  const proto = h.get("x-forwarded-proto") ?? (hostname === "localhost" || hostname.endsWith(".localhost") ? "http" : "https");

  if (root && (hostname === root || hostname.endsWith(`.${root}`))) return `${proto}://${slug}.${rootFull}`;
  return `${proto}://${host}/b/${slug}`;
}
EOF

# ---------- onboarding: address hint follows the same rule ----------
cat > "src/app/dashboard/(auth)/onboarding/form.tsx" <<'EOF'
"use client";

import { useActionState } from "react";
import { createTenant, type FormState } from "./actions";

export default function OnboardingForm({ prefix, suffix }: { prefix: string; suffix: string }) {
  const [state, action, pending] = useActionState<FormState, FormData>(createTenant, undefined);

  return (
    <form action={action} className="form">
      <label>
        Business name
        <input name="name" required placeholder="Glow Salon" className="field" />
      </label>
      <label>
        Your booking page address
        <div className="field-group">
          {prefix && <span className="suffix" style={{ paddingLeft: "0.95rem" }}>{prefix}</span>}
          <input name="slug" required placeholder="glow-salon" autoCapitalize="none" />
          {suffix && <span className="suffix">{suffix}</span>}
        </div>
      </label>
      <label>
        Type of business
        <select name="type" required defaultValue="salon" className="field">
          <option value="salon">Salon</option>
          <option value="barber">Barber</option>
          <option value="clinic">Clinic</option>
          <option value="venue">Event space</option>
        </select>
      </label>
      {state?.error && <p className="alert" role="alert">{state.error}</p>}
      <button disabled={pending} className="btn">{pending ? "Creating..." : "Create my booking page"}</button>
    </form>
  );
}
EOF

cat > "src/app/dashboard/(auth)/onboarding/page.tsx" <<'EOF'
import { redirect } from "next/navigation";
import { publicUrl } from "@/lib/context";
import { getSession } from "@/lib/session";
import OnboardingForm from "./form";

export default async function Onboarding() {
  const session = await getSession();
  if (!session) redirect("/login");

  const sample = await publicUrl("SLUG");
  const [prefix, suffix] = sample.replace(/^https?:\/\//, "").split("SLUG");

  return (
    <div className="glass auth enter">
      <h1 className="display h-md">Set up your business</h1>
      <p className="muted">This creates your public booking page. You can add services and staff next.</p>
      <OnboardingForm prefix={prefix} suffix={suffix} />
    </div>
  );
}
EOF

# ---------- patch existing files ----------
cat > patch-path-mode.mjs <<'PATCH_EOF'
import { readFileSync, writeFileSync } from "node:fs";

function patch(file, marker, edits) {
  let s = readFileSync(file, "utf8");
  if (s.includes(marker)) {
    console.log("already patched:", file);
    return;
  }
  for (const [from, to] of edits) {
    if (!s.includes(from)) throw new Error(`Could not find this text in ${file}:\n${from}`);
    s = s.replaceAll(from, to);
  }
  writeFileSync(file, s);
  console.log("patched:", file);
}

const IMPORT_BASE = 'import { basePath } from "@/lib/base";';

patch("src/app/sites/[tenant]/page.tsx", "@/lib/base", [
  ['import { getSlots } from "@/lib/slots";', 'import { getSlots } from "@/lib/slots";\n' + IMPORT_BASE],
  ["  const sp = await searchParams;", "  const sp = await searchParams;\n  const base = await basePath();"],
  ["return `/book?${q.toString()}`;", "return `${base}/book?${q.toString()}`;"],
]);

patch("src/app/sites/[tenant]/book/page.tsx", "@/lib/base", [
  ['import { getSlots } from "@/lib/slots";', 'import { getSlots } from "@/lib/slots";\n' + IMPORT_BASE],
  ["  const sp = await searchParams;", "  const sp = await searchParams;\n  const base = await basePath();"],
  ["const back = `/?${backQuery.toString()}`;", "const back = `${base}/?${backQuery.toString()}`;"],
]);

patch("src/app/sites/[tenant]/booking/[token]/page.tsx", "@/lib/base", [
  ['import { getTenantBySlug } from "@/lib/tenant";', 'import { getTenantBySlug } from "@/lib/tenant";\n' + IMPORT_BASE],
  ["  const { tenant: slug, token } = await params;", "  const { tenant: slug, token } = await params;\n  const base = await basePath();"],
  ['<Link href="/" className="btn">Book another time</Link>', '<Link href={base || "/"} className="btn">Book another time</Link>'],
]);

patch("src/app/sites/[tenant]/actions.ts", "@/lib/base", [
  ['import { isUuid } from "@/lib/ids";', 'import { isUuid } from "@/lib/ids";\n' + IMPORT_BASE],
  ["redirect(`/booking/${token}`);", "redirect(`${await basePath()}/booking/${token}`);"],
]);

patch("src/app/dashboard/(app)/layout.tsx", "await publicUrl(", [
  [
    "  const { session, tenant } = await requireTenant();",
    "  const { session, tenant } = await requireTenant();\n  const url = await publicUrl(tenant.slug);",
  ],
  ["href={publicUrl(tenant.slug)}", "href={url}"],
]);

patch("src/app/dashboard/(app)/page.tsx", "await publicUrl(", [
  ["const url = publicUrl(tenant.slug);", "const url = await publicUrl(tenant.slug);"],
]);
PATCH_EOF

node patch-path-mode.mjs
rm -f patch-path-mode.mjs

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
