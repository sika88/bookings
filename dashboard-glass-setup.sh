#!/usr/bin/env bash
set -e

mkdir -p src/styles src/components src/lib \
  "src/app/dashboard/(auth)" \
  "src/app/dashboard/(app)/services/[id]" \
  "src/app/dashboard/(app)/staff/[id]" \
  "src/app/dashboard/(app)/bookings"

# ---------- move shared css + auth pages ----------
if [ -f "src/app/sites/[tenant]/glass.css" ]; then
  mv "src/app/sites/[tenant]/glass.css" src/styles/glass.css
fi
sed -i 's#import "./glass.css";#import "@/styles/glass.css";#' "src/app/sites/[tenant]/layout.tsx"

for d in login signup onboarding; do
  if [ -d "src/app/dashboard/$d" ] && [ ! -d "src/app/dashboard/(auth)/$d" ]; then
    mv "src/app/dashboard/$d" "src/app/dashboard/(auth)/$d"
  fi
done

# ---------- shared bits ----------
cat > src/components/icons.tsx <<'EOF'
const base = {
  viewBox: "0 0 16 16",
  width: "1em",
  height: "1em",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

export function Check() {
  return (
    <svg {...base} strokeWidth={2} className="draw">
      <path pathLength={1} d="M3.5 8.5l3 3 6-7" />
    </svg>
  );
}
export function Cross() {
  return (
    <svg {...base} strokeWidth={2} className="draw">
      <path pathLength={1} d="M4 4l8 8M12 4l-8 8" />
    </svg>
  );
}
export function Clock() {
  return (
    <svg {...base}>
      <circle cx="8" cy="8" r="6" />
      <path d="M8 4.8V8l2.2 1.4" />
    </svg>
  );
}
export function Chevron() {
  return (
    <svg {...base}>
      <path d="M10 3L5 8l5 5" />
    </svg>
  );
}
export function Users() {
  return (
    <svg {...base} strokeWidth={1.6}>
      <circle cx="6" cy="6" r="2.4" />
      <path d="M1.8 13c.4-2.2 2.1-3.4 4.2-3.4S9.8 10.8 10.2 13" />
      <path d="M10.6 3.8a2.3 2.3 0 010 4.4M12 9.8c1.3.4 2.1 1.4 2.4 3.2" />
    </svg>
  );
}
export function Grid() {
  return (
    <svg {...base}>
      <rect x="2" y="2" width="5" height="5" rx="1.3" />
      <rect x="9" y="2" width="5" height="5" rx="1.3" />
      <rect x="2" y="9" width="5" height="5" rx="1.3" />
      <rect x="9" y="9" width="5" height="5" rx="1.3" />
    </svg>
  );
}
export function List() {
  return (
    <svg {...base}>
      <path d="M3 4h10M3 8h10M3 12h6" />
    </svg>
  );
}
export function Calendar() {
  return (
    <svg {...base}>
      <rect x="2" y="3" width="12" height="11" rx="2" />
      <path d="M2 7h12M5.5 1.5v3M10.5 1.5v3" />
    </svg>
  );
}
export function External() {
  return (
    <svg {...base}>
      <path d="M9 2.5h4.5V7M13.5 2.5L7.5 8.5M12 9.5v3a1 1 0 01-1 1H3.5a1 1 0 01-1-1V5a1 1 0 011-1h3" />
    </svg>
  );
}
EOF

cat > "src/app/sites/[tenant]/icons.tsx" <<'EOF'
export * from "@/components/icons";
EOF

cat > src/components/aurora.tsx <<'EOF'
export default function Aurora() {
  return (
    <div className="aurora" aria-hidden="true">
      <i /><i /><i />
      <b /><b /><b />
    </div>
  );
}
EOF

cat > src/lib/css.ts <<'EOF'
import type { CSSProperties } from "react";

// stagger index for entrance animations
export const num = (i: number) => ({ "--i": i }) as CSSProperties;
export const hueVar = (h: number) => ({ "--ah": h }) as CSSProperties;
export const statusHue = (h: number) => ({ "--s": h }) as CSSProperties;
EOF

cat > src/lib/format.ts <<'EOF'
export function formatWhen(d: Date, tz: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    weekday: "long",
    day: "numeric",
    month: "long",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}

export function formatTime(d: Date, tz: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}

export function formatDay(d: Date, tz: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(d);
}
EOF

cat > src/components/action-form.tsx <<'EOF'
"use client";

import { useActionState } from "react";
import { Check } from "./icons";

export type ActionState = { error?: string; ok?: boolean } | undefined;

export default function ActionForm({
  action,
  submitLabel,
  children,
  className = "form flush",
}: {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  submitLabel: string;
  children: React.ReactNode;
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, undefined);

  return (
    <form action={formAction} className={className}>
      {children}
      {state?.error && <p className="alert" role="alert">{state.error}</p>}
      <div className="form-foot">
        <button disabled={pending} className="btn btn-inline">
          {pending ? "Saving..." : submitLabel}
        </button>
        {state?.ok && (
          <span className="saved" role="status">
            <Check /> Saved
          </span>
        )}
      </div>
    </form>
  );
}
EOF

# ---------- dashboard styles ----------
cat > src/styles/dash.css <<'EOF'
/* Dashboard additions on top of glass.css */

.glass-root { color-scheme: dark; }
.glass-root select option { background: #12162b; color: #f4f6ff; }
.link { color: var(--accent); text-decoration: underline; text-underline-offset: 3px; }

/* ---------- shell ---------- */
.dash { max-width: 80rem; margin: 0 auto; padding: 1rem; display: grid; gap: 1rem; }
.main { min-width: 0; display: grid; gap: 1.25rem; align-content: start; padding-bottom: 3rem; }
.sidebar { padding: 1rem; }
@media (min-width: 1024px) {
  .dash { grid-template-columns: 17rem minmax(0, 1fr); gap: 1.5rem; padding: 1.5rem; align-items: start; }
  .sidebar { position: sticky; top: 1.5rem; height: calc(100vh - 3rem); display: flex; flex-direction: column; padding: 1.25rem; }
}
.side-brand { display: flex; align-items: center; gap: 0.75rem; }
.side-brand .monogram { width: 2.6rem; height: 2.6rem; font-size: 1.2rem; border-radius: 13px; flex: none; }
.side-name { font-family: var(--font-display), sans-serif; font-weight: 700; letter-spacing: -0.02em; line-height: 1.1; overflow-wrap: anywhere; }

.nav { display: flex; gap: 0.35rem; margin-top: 1rem; overflow-x: auto; scrollbar-width: none; }
.nav::-webkit-scrollbar { display: none; }
@media (min-width: 1024px) { .nav { flex-direction: column; margin-top: 1.75rem; overflow: visible; } }
.nav-link {
  display: flex; align-items: center; gap: 0.7rem; padding: 0.65rem 0.95rem; border-radius: 14px; white-space: nowrap;
  color: var(--muted); font-weight: 500; transition: background 0.2s, color 0.2s, transform 0.2s;
}
.nav-link svg { font-size: 1.1rem; }
.nav-link:hover { background: rgba(255, 255, 255, 0.08); color: var(--text); }
.nav-link:active { transform: scale(0.98); }
.nav-link.active {
  color: var(--text); background: linear-gradient(135deg, hsl(var(--h) 95% 62% / 0.3), hsl(calc(var(--h) + 55) 95% 60% / 0.18));
  box-shadow: inset 0 0 0 1px hsl(var(--h) 100% 78% / 0.45);
}

.side-foot { display: flex; flex-wrap: wrap; align-items: center; gap: 0.6rem; margin-top: 0.9rem; }
@media (min-width: 1024px) { .side-foot { flex-direction: column; align-items: stretch; margin-top: auto; } }
.side-email { overflow-wrap: anywhere; }

/* ---------- buttons ---------- */
.act {
  display: inline-flex; align-items: center; justify-content: center; gap: 0.4rem; padding: 0.5rem 1rem; border-radius: 999px; font: inherit; font-size: 0.88rem;
  color: var(--text); cursor: pointer; background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line); transition: background 0.2s, transform 0.2s;
}
.act:hover { background: rgba(255, 255, 255, 0.14); }
.act:active { transform: scale(0.97); }
.act.primary { color: var(--ink); border-color: transparent; background: linear-gradient(120deg, var(--accent), var(--accent-2)); }
.act.danger { color: #ffb4b4; border-color: rgba(255, 130, 130, 0.45); }
.btn-inline { display: inline-block; width: auto; padding: 0.8rem 1.6rem; }
.form.flush { margin-top: 0; }
.form-foot { display: flex; align-items: center; gap: 1rem; }
.saved { display: inline-flex; align-items: center; gap: 0.4rem; color: hsl(150 90% 75%); font-size: 0.9rem; animation: swap 0.4s both; }

/* ---------- page structure ---------- */
.page-head { display: flex; flex-wrap: wrap; align-items: flex-end; justify-content: space-between; gap: 1rem; padding: 0.25rem 0.25rem 0; }
.page-head h1 { font-size: clamp(1.8rem, 3vw, 2.5rem); line-height: 1; }
.page-head p { margin-top: 0.5rem; }
.split { display: grid; gap: 1.25rem; }
@media (min-width: 1100px) {
  .split { grid-template-columns: minmax(0, 1fr) 24rem; align-items: start; }
  .split > .sticky { position: sticky; top: 1.5rem; }
}
.panel-title { font-family: var(--font-display), sans-serif; font-weight: 600; font-size: 1.25rem; letter-spacing: -0.02em; margin-bottom: 1rem; }
.list { display: grid; gap: 0.7rem; list-style: none; padding: 0; margin: 0; }

.item {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.75rem 1rem; padding: 1rem 1.1rem; border-radius: 18px;
  background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line); transition: background 0.2s, border-color 0.2s;
}
.item:hover { background: rgba(255, 255, 255, 0.1); border-color: var(--line-strong); }
.item.off { opacity: 0.55; }
.item-title { display: flex; align-items: center; gap: 0.6rem; font-family: var(--font-display), sans-serif; font-weight: 600; font-size: 1.1rem; letter-spacing: -0.02em; }
.item-actions { display: flex; align-items: center; gap: 0.5rem; }
.item-lead { display: flex; align-items: center; gap: 0.9rem; }
.empty-state { padding: 2rem 0.5rem; text-align: center; }

/* ---------- overview ---------- */
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr)); gap: 1rem; }
.stat { padding: 1.25rem; }
.stat-num { font-family: var(--font-display), sans-serif; font-size: 2.5rem; font-weight: 700; letter-spacing: -0.04em; line-height: 1; }
.stat-label { margin-top: 0.45rem; color: var(--muted); font-size: 0.88rem; }
.link-card { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.75rem 1rem; padding: 1.1rem 1.4rem; }
.link-url { font-weight: 500; overflow-wrap: anywhere; }
.todo { display: flex; align-items: center; gap: 0.8rem; padding: 0.85rem 1rem; border-radius: 16px; background: rgba(255, 255, 255, 0.06); border: 1px solid var(--line); }

/* ---------- bookings ---------- */
.day-head { font-family: var(--font-display), sans-serif; font-weight: 600; font-size: 1.1rem; letter-spacing: -0.02em; margin: 0.75rem 0.25rem 0.6rem; }
.day-head:first-child { margin-top: 0; }
.bk {
  display: grid; grid-template-columns: 4.5rem minmax(0, 1fr); gap: 0.4rem 1rem; padding: 1rem 1.1rem; border-radius: 18px;
  background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line);
}
.bk.off { opacity: 0.5; }
.bk-time { font-family: var(--font-display), sans-serif; font-weight: 700; font-size: 1.5rem; letter-spacing: -0.03em; font-variant-numeric: tabular-nums; display: grid; line-height: 1.1; }
.bk-side { grid-column: 2; display: flex; flex-wrap: wrap; align-items: center; gap: 0.6rem; }
.bk-actions { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 0.5rem; padding-top: 0.5rem; border-top: 1px solid var(--line); margin-top: 0.4rem; }
@media (min-width: 720px) {
  .bk { grid-template-columns: 4.5rem minmax(0, 1fr) auto; }
  .bk-side { grid-column: 3; flex-direction: column; align-items: flex-end; gap: 0.3rem; text-align: right; }
}
.status {
  display: inline-flex; padding: 0.2rem 0.7rem; border-radius: 999px; font-size: 0.78rem; font-weight: 600;
  background: hsl(var(--s) 90% 60% / 0.18); border: 1px solid hsl(var(--s) 100% 75% / 0.5); color: hsl(var(--s) 100% 84%);
}

/* ---------- form controls ---------- */
.two { display: grid; gap: 0.9rem; }
@media (min-width: 520px) { .two { grid-template-columns: 1fr 1fr; } }
select.field {
  appearance: none; -webkit-appearance: none; padding-right: 2.5rem; cursor: pointer;
  background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8' fill='none' stroke='%23c9cfff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M1 1.5l5 5 5-5'/></svg>");
  background-repeat: no-repeat; background-position: right 1rem center;
}
.fieldset { border: 0; padding: 0; margin: 0; min-width: 0; }
.fieldset legend { font-size: 0.85rem; color: var(--muted); margin-bottom: 0.55rem; padding: 0; }
.chips { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.form .chip {
  position: relative; display: inline-flex; align-items: center; gap: 0.55rem; padding: 0.5rem 1rem 0.5rem 0.85rem; border-radius: 999px;
  background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line); color: var(--text); font-size: 0.9rem; cursor: pointer;
  transition: background 0.2s, border-color 0.2s, transform 0.2s;
}
.form .chip:hover { background: rgba(255, 255, 255, 0.12); }
.form .chip:active { transform: scale(0.97); }
.chip::before { content: ""; width: 0.6rem; height: 0.6rem; border-radius: 50%; border: 1.5px solid var(--line-strong); transition: background 0.2s, border-color 0.2s, box-shadow 0.2s; }
.chip input { position: absolute; inset: 0; width: 100%; height: 100%; margin: 0; opacity: 0; cursor: pointer; }
.chip:has(input:checked) { background: hsl(var(--h) 95% 62% / 0.28); border-color: hsl(var(--h) 100% 78% / 0.7); }
.chip:has(input:checked)::before { background: var(--accent); border-color: transparent; box-shadow: 0 0 10px hsl(var(--h) 100% 65% / 0.8); }
.chip:has(input:focus-visible) { outline: 2px solid var(--accent); outline-offset: 3px; }

.form .switch { position: relative; display: flex; align-items: center; gap: 0.75rem; color: var(--text); font-size: 0.95rem; cursor: pointer; }
.switch input { position: absolute; left: 0; top: 0; width: 2.6rem; height: 1.5rem; margin: 0; opacity: 0; cursor: pointer; }
.switch .track { position: relative; flex: none; width: 2.6rem; height: 1.5rem; border-radius: 99px; background: rgba(255, 255, 255, 0.14); border: 1px solid var(--line); transition: background 0.25s; }
.switch .track::after {
  content: ""; position: absolute; top: 2px; left: 2px; width: calc(1.5rem - 6px); height: calc(1.5rem - 6px); border-radius: 50%; background: #fff;
  transition: transform 0.25s cubic-bezier(0.3, 1.4, 0.5, 1);
}
.switch input:checked + .track { background: linear-gradient(120deg, var(--accent), var(--accent-2)); border-color: transparent; }
.switch input:checked + .track::after { transform: translateX(1.1rem); }
.switch input:focus-visible + .track { outline: 2px solid var(--accent); outline-offset: 3px; }

.hours { display: grid; }
.hours-row { display: grid; gap: 0.5rem; padding: 0.8rem 0; border-top: 1px solid var(--line); align-items: center; }
.hours-row:first-child { border-top: 0; }
@media (min-width: 720px) { .hours-row { grid-template-columns: 7.5rem 1fr 1fr; gap: 1rem; } }
.hours-row .day-label { font-weight: 500; }
.range { display: flex; align-items: center; gap: 0.5rem; }
.range .field { padding: 0.55rem 0.7rem; font-size: 0.95rem; }
.range .to { color: var(--muted); font-size: 0.85rem; }

.field-group { display: flex; align-items: center; border-radius: 14px; background: rgba(255, 255, 255, 0.08); border: 1px solid var(--line); padding-right: 0.95rem; transition: border-color 0.2s, background 0.2s; }
.field-group:focus-within { background: rgba(255, 255, 255, 0.12); border-color: hsl(var(--h) 100% 78% / 0.8); }
.field-group input { flex: 1; min-width: 0; padding: 0.8rem 0.95rem; border: 0; background: transparent; color: var(--text); font: inherit; font-size: 1rem; outline: none; }
.field-group .suffix { color: var(--muted); font-size: 0.9rem; white-space: nowrap; }

/* ---------- auth ---------- */
.auth-wrap { position: relative; min-height: 100vh; display: grid; place-items: center; padding: 1.25rem; }
.auth { width: 100%; max-width: 26rem; padding: 2rem; }
.auth .h-md { margin-bottom: 0.5rem; }
.auth .form { margin-top: 1.25rem; }
EOF

cat > "src/app/dashboard/layout.tsx" <<'EOF'
import { Bricolage_Grotesque, Instrument_Sans } from "next/font/google";
import "@/styles/glass.css";
import "@/styles/dash.css";

const display = Bricolage_Grotesque({ subsets: ["latin"], variable: "--font-display", display: "swap" });
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body", display: "swap" });

export const metadata = { title: "Dashboard" };

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <div className={`${display.variable} ${body.variable} glass-root`}>{children}</div>;
}
EOF

cat > "src/app/dashboard/sign-out-button.tsx" <<'EOF'
"use client";

import { useRouter } from "next/navigation";
import { authClient } from "@/lib/auth-client";

export default function SignOutButton() {
  const router = useRouter();
  return (
    <button
      className="act"
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

# ---------- auth pages ----------
cat > "src/app/dashboard/(auth)/layout.tsx" <<'EOF'
import Aurora from "@/components/aurora";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <Aurora />
      <main className="auth-wrap">{children}</main>
    </>
  );
}
EOF

cat > "src/app/dashboard/(auth)/login/page.tsx" <<'EOF'
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
    <div className="glass auth enter">
      <h1 className="display h-md">Welcome back</h1>
      <p className="muted">Log in to manage your bookings.</p>
      <form onSubmit={onSubmit} className="form">
        <label>
          Email
          <input name="email" type="email" required autoComplete="email" className="field" />
        </label>
        <label>
          Password
          <input name="password" type="password" required autoComplete="current-password" className="field" />
        </label>
        {error && <p className="alert" role="alert">{error}</p>}
        <button disabled={loading} className="btn">{loading ? "Logging in..." : "Log in"}</button>
      </form>
      <p className="muted small" style={{ marginTop: "1.25rem" }}>
        New here? <Link href="/signup" className="link">Create an account</Link>
      </p>
    </div>
  );
}
EOF

cat > "src/app/dashboard/(auth)/signup/page.tsx" <<'EOF'
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
    <div className="glass auth enter">
      <h1 className="display h-md">Create your account</h1>
      <p className="muted">Set up online booking for your business in a few minutes.</p>
      <form onSubmit={onSubmit} className="form">
        <label>
          Your name
          <input name="name" required autoComplete="name" className="field" />
        </label>
        <label>
          Email
          <input name="email" type="email" required autoComplete="email" className="field" />
        </label>
        <label>
          Password
          <input name="password" type="password" minLength={8} required autoComplete="new-password" placeholder="At least 8 characters" className="field" />
        </label>
        {error && <p className="alert" role="alert">{error}</p>}
        <button disabled={loading} className="btn">{loading ? "Creating..." : "Sign up"}</button>
      </form>
      <p className="muted small" style={{ marginTop: "1.25rem" }}>
        Already have an account? <Link href="/login" className="link">Log in</Link>
      </p>
    </div>
  );
}
EOF

cat > "src/app/dashboard/(auth)/onboarding/form.tsx" <<'EOF'
"use client";

import { useActionState } from "react";
import { createTenant, type FormState } from "./actions";

export default function OnboardingForm({ rootDomain }: { rootDomain: string }) {
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
          <input name="slug" required placeholder="glow-salon" autoCapitalize="none" />
          <span className="suffix">.{rootDomain}</span>
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
import { getSession } from "@/lib/session";
import OnboardingForm from "./form";

export default async function Onboarding() {
  const session = await getSession();
  if (!session) redirect("/login");

  return (
    <div className="glass auth enter">
      <h1 className="display h-md">Set up your business</h1>
      <p className="muted">This creates your public booking page. You can add services and staff next.</p>
      <OnboardingForm rootDomain={process.env.NEXT_PUBLIC_ROOT_DOMAIN!} />
    </div>
  );
}
EOF

# ---------- app shell ----------
cat > "src/app/dashboard/(app)/nav.tsx" <<'EOF'
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Calendar, Grid, List, Users } from "@/components/icons";

const items = [
  { href: "/", label: "Overview", Icon: Grid },
  { href: "/bookings", label: "Bookings", Icon: Calendar },
  { href: "/services", label: "Services", Icon: List },
  { href: "/staff", label: "Staff", Icon: Users },
];

export default function Nav() {
  const raw = usePathname();
  // the proxy rewrites app.* requests to /dashboard/*, so normalise both forms
  const path = raw.replace(/^\/dashboard(?=\/|$)/, "") || "/";

  return (
    <nav className="nav" aria-label="Dashboard">
      {items.map(({ href, label, Icon }) => {
        const active = href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`);
        return (
          <Link key={href} href={href} aria-current={active ? "page" : undefined} className={`nav-link${active ? " active" : ""}`}>
            <Icon />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
EOF

cat > "src/app/dashboard/(app)/layout.tsx" <<'EOF'
import type { CSSProperties } from "react";
import Aurora from "@/components/aurora";
import { External } from "@/components/icons";
import { publicUrl, requireTenant } from "@/lib/context";
import { hueOf } from "@/lib/hue";
import SignOutButton from "../sign-out-button";
import Nav from "./nav";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { session, tenant } = await requireTenant();

  return (
    <div className="dash" style={{ "--h": hueOf(tenant.slug) } as CSSProperties}>
      <Aurora />
      <aside className="glass sidebar enter">
        <div className="side-brand">
          <div className="monogram">{tenant.name.charAt(0).toUpperCase()}</div>
          <div className="side-name">{tenant.name}</div>
        </div>
        <Nav />
        <div className="side-foot">
          <a href={publicUrl(tenant.slug)} target="_blank" rel="noreferrer" className="act primary">
            View booking page <External />
          </a>
          <div className="muted small side-email">{session.user.email}</div>
          <SignOutButton />
        </div>
      </aside>
      <div className="main">{children}</div>
    </div>
  );
}
EOF

cat > "src/app/dashboard/(app)/page-head.tsx" <<'EOF'
import type { ReactNode } from "react";
import { num } from "@/lib/css";

export default function PageHead({ title, sub, children }: { title: string; sub?: string; children?: ReactNode }) {
  return (
    <header className="page-head enter" style={num(0)}>
      <div>
        <h1 className="display">{title}</h1>
        {sub && <p className="muted">{sub}</p>}
      </div>
      {children}
    </header>
  );
}
EOF

cat > "src/app/dashboard/(app)/booking-card.tsx" <<'EOF'
import type { ReactNode } from "react";
import type { bookings } from "@/db/schema";
import { statusHue } from "@/lib/css";
import { formatTime, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";

type Booking = typeof bookings.$inferSelect;

const STATUS: Record<string, { label: string; hue: number }> = {
  pending: { label: "Awaiting deposit", hue: 38 },
  confirmed: { label: "Confirmed", hue: 150 },
  completed: { label: "Completed", hue: 200 },
  cancelled: { label: "Cancelled", hue: 0 },
  no_show: { label: "No-show", hue: 20 },
};

export default function BookingCard({
  b,
  service,
  staffName,
  customer,
  phone,
  tz,
  showDate,
  actions,
}: {
  b: Booking;
  service: string;
  staffName: string;
  customer: string;
  phone: string;
  tz: string;
  showDate?: boolean;
  actions?: ReactNode;
}) {
  const st = STATUS[b.status] ?? { label: b.status, hue: 220 };

  return (
    <li className={`bk${b.status === "cancelled" ? " off" : ""}`}>
      <div className="bk-time">
        {formatTime(b.startsAt, tz)}
        <span className="muted small">{formatTime(b.endsAt, tz)}</span>
      </div>
      <div className="bk-main">
        <div className="item-title">{service}</div>
        {showDate && <div className="muted small">{formatWhen(b.startsAt, tz)}</div>}
        <div className="muted small">with {staffName}</div>
        <div className="small">
          {customer} <span className="muted">{phone}</span>
        </div>
        {b.notes && <div className="muted small">Note: {b.notes}</div>}
      </div>
      <div className="bk-side">
        <span className="status" style={statusHue(st.hue)}>{st.label}</span>
        <span className="muted small">
          {formatMoney(b.totalPesewas)}
          {b.depositPesewas > 0 ? `, deposit ${formatMoney(b.depositPesewas)}` : ""}
        </span>
      </div>
      {actions && <div className="bk-actions">{actions}</div>}
    </li>
  );
}
EOF

# ---------- overview ----------
cat > "src/app/dashboard/(app)/page.tsx" <<'EOF'
import Link from "next/link";
import { and, asc, count, eq, gt, gte, inArray } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { Check } from "@/components/icons";
import { publicUrl, requireTenant } from "@/lib/context";
import { expireHolds } from "@/lib/bookings";
import { num } from "@/lib/css";
import BookingCard from "./booking-card";
import PageHead from "./page-head";

export default async function Overview() {
  const { tenant } = await requireTenant();
  await expireHolds(tenant.id);
  const now = new Date();

  const [[svc], [stf], [upcoming], [holds], next] = await Promise.all([
    db.select({ n: count() }).from(services).where(and(eq(services.tenantId, tenant.id), eq(services.active, true))),
    db.select({ n: count() }).from(staff).where(and(eq(staff.tenantId, tenant.id), eq(staff.active, true))),
    db
      .select({ n: count() })
      .from(bookings)
      .where(and(eq(bookings.tenantId, tenant.id), eq(bookings.status, "confirmed"), gte(bookings.startsAt, now))),
    db
      .select({ n: count() })
      .from(bookings)
      .where(and(eq(bookings.tenantId, tenant.id), eq(bookings.status, "pending"), gt(bookings.holdExpiresAt, now))),
    db
      .select({ b: bookings, service: services.name, staffName: staff.displayName, customer: customers.name, phone: customers.phone })
      .from(bookings)
      .innerJoin(services, eq(bookings.serviceId, services.id))
      .innerJoin(staff, eq(bookings.staffId, staff.id))
      .innerJoin(customers, eq(bookings.customerId, customers.id))
      .where(and(eq(bookings.tenantId, tenant.id), inArray(bookings.status, ["pending", "confirmed"]), gte(bookings.startsAt, now)))
      .orderBy(asc(bookings.startsAt))
      .limit(5),
  ]);

  const url = publicUrl(tenant.slug);
  const steps = [
    { done: svc.n > 0, label: "Add at least one service", href: "/services" },
    { done: stf.n > 0, label: "Add a staff member and set their working hours", href: "/staff" },
  ];
  const setupDone = steps.every((s) => s.done);

  const stats = [
    { n: upcoming.n, label: "Upcoming bookings" },
    { n: holds.n, label: "Awaiting deposit" },
    { n: svc.n, label: "Active services" },
    { n: stf.n, label: "Active staff" },
  ];

  return (
    <>
      <PageHead title="Overview" sub="Here is how your bookings are looking." />

      <section className="glass link-card enter" style={num(1)}>
        <div>
          <div className="muted small">Your booking page</div>
          <div className="link-url">{url}</div>
        </div>
        <a href={url} target="_blank" rel="noreferrer" className="act primary">Open page</a>
      </section>

      <div className="stats">
        {stats.map((s, i) => (
          <div key={s.label} className="glass stat enter" style={num(i + 2)}>
            <div className="stat-num">{s.n}</div>
            <div className="stat-label">{s.label}</div>
          </div>
        ))}
      </div>

      {!setupDone && (
        <section className="glass panel enter" style={num(3)}>
          <h2 className="panel-title">Finish setting up</h2>
          <div className="list">
            {steps.map((s) => (
              <div key={s.href} className="todo">
                <span className={`badge${s.done ? " done" : ""}`}>{s.done ? <Check /> : ""}</span>
                {s.done ? (
                  <span className="muted" style={{ textDecoration: "line-through" }}>{s.label}</span>
                ) : (
                  <Link href={s.href} className="link">{s.label}</Link>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="glass panel enter" style={num(4)}>
        <h2 className="panel-title">Next appointments</h2>
        {next.length === 0 ? (
          <p className="muted empty-state">No upcoming appointments yet. They will appear here as customers book.</p>
        ) : (
          <ul className="list">
            {next.map((r) => (
              <BookingCard key={r.b.id} b={r.b} service={r.service} staffName={r.staffName} customer={r.customer} phone={r.phone} tz={tenant.timezone} showDate />
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
EOF

# ---------- services ----------
cat > "src/app/dashboard/(app)/services/fields.tsx" <<'EOF'
import type { services } from "@/db/schema";

type Svc = typeof services.$inferSelect;

export default function ServiceFields({ service }: { service?: Svc }) {
  const depositDefault = !service
    ? ""
    : service.depositType === "fixed"
      ? (service.depositValue / 100).toFixed(2)
      : service.depositType === "percent"
        ? String(service.depositValue)
        : "";

  return (
    <>
      {service && <input type="hidden" name="id" value={service.id} />}

      <label>
        Name
        <input name="name" required defaultValue={service?.name} placeholder="Haircut" className="field" />
      </label>

      <label>
        Description (optional)
        <textarea name="description" rows={2} defaultValue={service?.description ?? ""} className="field" />
      </label>

      <div className="two">
        <label>
          Duration (minutes)
          <input name="durationMin" type="number" min={5} step={5} required defaultValue={service?.durationMin ?? 30} className="field" />
        </label>
        <label>
          Buffer after (minutes)
          <input name="bufferMin" type="number" min={0} step={5} required defaultValue={service?.bufferMin ?? 0} className="field" />
        </label>
      </div>

      <label>
        Price (GH₵)
        <input
          name="price"
          inputMode="decimal"
          required
          placeholder="50.00"
          defaultValue={service ? (service.pricePesewas / 100).toFixed(2) : ""}
          className="field"
        />
      </label>

      <div className="two">
        <label>
          Deposit
          <select name="depositType" defaultValue={service?.depositType ?? "none"} className="field">
            <option value="none">No deposit</option>
            <option value="fixed">Fixed amount (GH₵)</option>
            <option value="percent">Percentage of price</option>
          </select>
        </label>
        <label>
          Deposit value
          <input name="deposit" inputMode="decimal" defaultValue={depositDefault} placeholder="10.00 or 30" className="field" />
        </label>
      </div>
      <p className="muted small">
        Enter an amount in GH₵ for a fixed deposit, or a number from 1 to 100 for a percentage. It is ignored when there is no deposit.
      </p>
    </>
  );
}
EOF

cat > "src/app/dashboard/(app)/services/page.tsx" <<'EOF'
import Link from "next/link";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { requireTenant } from "@/lib/context";
import { num } from "@/lib/css";
import { formatMoney } from "@/lib/money";
import PageHead from "../page-head";
import { createService, setServiceActive } from "./actions";
import ServiceFields from "./fields";

export default async function ServicesPage() {
  const { tenant } = await requireTenant();
  const rows = await db.select().from(services).where(eq(services.tenantId, tenant.id)).orderBy(asc(services.name));

  return (
    <>
      <PageHead title="Services" sub="What your customers can book, and what it costs." />

      <div className="split">
        <section className="glass panel enter" style={num(1)}>
          {rows.length === 0 ? (
            <p className="muted empty-state">No services yet. Add your first one with the form.</p>
          ) : (
            <ul className="list">
              {rows.map((s, i) => (
                <li key={s.id} className={`item pop${s.active ? "" : " off"}`} style={num(i)}>
                  <div>
                    <div className="item-title">
                      {s.name}
                      {!s.active && <span className="pill">Hidden</span>}
                    </div>
                    {s.description && <div className="muted small">{s.description}</div>}
                    <div className="pills">
                      <span className="pill">{s.durationMin} min</span>
                      <span className="pill">{formatMoney(s.pricePesewas)}</span>
                      {s.depositType !== "none" && (
                        <span className="pill accent">
                          {s.depositType === "fixed" ? `${formatMoney(s.depositValue)} deposit` : `${s.depositValue}% deposit`}
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="item-actions">
                    <Link href={`/services/${s.id}`} className="act">Edit</Link>
                    <form action={setServiceActive}>
                      <input type="hidden" name="id" value={s.id} />
                      <input type="hidden" name="active" value={s.active ? "false" : "true"} />
                      <button className="act">{s.active ? "Hide" : "Show"}</button>
                    </form>
                  </div>
                </li>
              ))}
            </ul>
          )}
          {rows.length > 0 && (
            <p className="muted small" style={{ marginTop: "1rem" }}>
              Services can be hidden but not deleted, so past bookings keep their history.
            </p>
          )}
        </section>

        <section className="glass panel enter sticky" style={num(2)}>
          <h2 className="panel-title">Add a service</h2>
          <ActionForm action={createService} submitLabel="Add service">
            <ServiceFields />
          </ActionForm>
        </section>
      </div>
    </>
  );
}
EOF

cat > "src/app/dashboard/(app)/services/[id]/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { Chevron } from "@/components/icons";
import { requireTenant } from "@/lib/context";
import { num } from "@/lib/css";
import { isUuid } from "@/lib/ids";
import { updateService } from "../actions";
import ServiceFields from "../fields";

export default async function EditService({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { tenant } = await requireTenant();
  if (!isUuid(id)) notFound();

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, id), eq(services.tenantId, tenant.id)))
    .limit(1);
  if (!service) notFound();

  return (
    <>
      <Link href="/services" className="back enter" style={num(0)}>
        <Chevron /> Back to services
      </Link>
      <section className="glass panel enter" style={{ ...num(1), maxWidth: "36rem" }}>
        <h1 className="display h-md">Edit {service.name}</h1>
        <ActionForm action={updateService} submitLabel="Save changes">
          <ServiceFields service={service} />
        </ActionForm>
      </section>
    </>
  );
}
EOF

# ---------- staff ----------
cat > "src/app/dashboard/(app)/staff/page.tsx" <<'EOF'
import Link from "next/link";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { staff } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { requireTenant } from "@/lib/context";
import { hueVar, num } from "@/lib/css";
import { hueOf } from "@/lib/hue";
import PageHead from "../page-head";
import { createStaff } from "./actions";

export default async function StaffPage() {
  const { tenant } = await requireTenant();
  const rows = await db.select().from(staff).where(eq(staff.tenantId, tenant.id)).orderBy(asc(staff.displayName));

  return (
    <>
      <PageHead title="Staff" sub="The people customers can book with." />

      <div className="split">
        <section className="glass panel enter" style={num(1)}>
          {rows.length === 0 ? (
            <p className="muted empty-state">No staff yet. Add your first person with the form.</p>
          ) : (
            <ul className="list">
              {rows.map((s, i) => (
                <li key={s.id} className={`item pop${s.active ? "" : " off"}`} style={num(i)}>
                  <div className="item-lead">
                    <span className="avatar" style={hueVar(hueOf(s.displayName))}>{s.displayName.charAt(0).toUpperCase()}</span>
                    <div>
                      <div className="item-title">
                        {s.displayName}
                        {!s.active && <span className="pill">Hidden</span>}
                      </div>
                      {s.bio && <div className="muted small">{s.bio}</div>}
                    </div>
                  </div>
                  <Link href={`/staff/${s.id}`} className="act">Manage</Link>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="glass panel enter sticky" style={num(2)}>
          <h2 className="panel-title">Add a staff member</h2>
          <ActionForm action={createStaff} submitLabel="Add staff member">
            <label>
              Name
              <input name="displayName" required placeholder="Ama" className="field" />
            </label>
            <label>
              Short bio (optional)
              <input name="bio" className="field" />
            </label>
            <p className="muted small">
              New staff start with all your active services and Monday to Saturday, 09:00 to 18:00. You can change both on the next page.
            </p>
          </ActionForm>
        </section>
      </div>
    </>
  );
}
EOF

cat > "src/app/dashboard/(app)/staff/[id]/page.tsx" <<'EOF'
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { db } from "@/db";
import { availabilityRules, services, staff, staffServices } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { Chevron } from "@/components/icons";
import { requireTenant } from "@/lib/context";
import { hueVar, num } from "@/lib/css";
import { hueOf } from "@/lib/hue";
import { isUuid } from "@/lib/ids";
import { saveHours, updateStaff } from "../actions";
import { DAYS } from "../days";

export default async function StaffDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { tenant } = await requireTenant();
  if (!isUuid(id)) notFound();

  const [member] = await db
    .select()
    .from(staff)
    .where(and(eq(staff.id, id), eq(staff.tenantId, tenant.id)))
    .limit(1);
  if (!member) notFound();

  const [allServices, linked, rules] = await Promise.all([
    db.select().from(services).where(eq(services.tenantId, tenant.id)).orderBy(asc(services.name)),
    db.select({ serviceId: staffServices.serviceId }).from(staffServices).where(eq(staffServices.staffId, member.id)),
    db
      .select()
      .from(availabilityRules)
      .where(and(eq(availabilityRules.staffId, member.id), eq(availabilityRules.tenantId, tenant.id))),
  ]);

  const linkedIds = new Set(linked.map((l) => l.serviceId));

  const byDay = new Map<number, { s: string; e: string }[]>();
  for (const r of [...rules].sort((a, b) => a.startTime.localeCompare(b.startTime))) {
    const list = byDay.get(r.weekday) ?? [];
    list.push({ s: r.startTime.slice(0, 5), e: r.endTime.slice(0, 5) });
    byDay.set(r.weekday, list);
  }

  return (
    <>
      <Link href="/staff" className="back enter" style={num(0)}>
        <Chevron /> Back to staff
      </Link>

      <header className="item-lead enter" style={num(1)}>
        <span className="avatar" style={{ ...hueVar(hueOf(member.displayName)), width: "3.2rem", height: "3.2rem", fontSize: "1.3rem" }}>
          {member.displayName.charAt(0).toUpperCase()}
        </span>
        <h1 className="display h-md" style={{ marginBottom: 0 }}>{member.displayName}</h1>
      </header>

      <section className="glass panel enter" style={{ ...num(2), maxWidth: "44rem" }}>
        <h2 className="panel-title">Profile and services</h2>
        <ActionForm action={updateStaff} submitLabel="Save profile">
          <input type="hidden" name="id" value={member.id} />
          <label>
            Name
            <input name="displayName" required defaultValue={member.displayName} className="field" />
          </label>
          <label>
            Short bio (optional)
            <input name="bio" defaultValue={member.bio ?? ""} className="field" />
          </label>

          <fieldset className="fieldset">
            <legend>Services this person offers</legend>
            {allServices.length === 0 ? (
              <p className="muted small">
                No services yet. <Link href="/services" className="link">Add a service</Link> first.
              </p>
            ) : (
              <div className="chips">
                {allServices.map((s) => (
                  <label key={s.id} className="chip">
                    <input type="checkbox" name="serviceId" value={s.id} defaultChecked={linkedIds.has(s.id)} />
                    <span>{s.name}</span>
                    {!s.active && <small className="muted">hidden</small>}
                  </label>
                ))}
              </div>
            )}
          </fieldset>

          <label className="switch">
            <input type="checkbox" name="active" defaultChecked={member.active} />
            <span className="track" aria-hidden="true" />
            Show on the booking page
          </label>
          <p className="muted small">Turning this off hides this person from new bookings. Existing bookings are kept.</p>
        </ActionForm>
      </section>

      <section className="glass panel enter" style={{ ...num(3), maxWidth: "44rem" }}>
        <h2 className="panel-title">Working hours</h2>
        <p className="muted small" style={{ marginTop: "-0.5rem", marginBottom: "0.75rem" }}>
          Leave a day empty for a day off. Use the second range for a break, for example 09:00 to 13:00, then 14:00 to 18:00.
        </p>
        <ActionForm action={saveHours} submitLabel="Save hours">
          <input type="hidden" name="id" value={member.id} />
          <div className="hours">
            {DAYS.map(({ weekday, label }) => {
              const ranges = byDay.get(weekday) ?? [];
              return (
                <div key={weekday} className="hours-row">
                  <span className="day-label">{label}</span>
                  {[1, 2].map((n) => (
                    <div key={n} className="range">
                      <input type="time" name={`d${weekday}_s${n}`} defaultValue={ranges[n - 1]?.s ?? ""} className="field" aria-label={`${label} range ${n} start`} />
                      <span className="to">to</span>
                      <input type="time" name={`d${weekday}_e${n}`} defaultValue={ranges[n - 1]?.e ?? ""} className="field" aria-label={`${label} range ${n} end`} />
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        </ActionForm>
      </section>
    </>
  );
}
EOF

# ---------- bookings ----------
cat > "src/app/dashboard/(app)/bookings/page.tsx" <<'EOF'
import { and, asc, eq, gte } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { expireHolds } from "@/lib/bookings";
import { num } from "@/lib/css";
import { formatDay } from "@/lib/format";
import BookingCard from "../booking-card";
import PageHead from "../page-head";
import { setBookingStatus } from "./actions";

function Action({ id, status, label, danger }: { id: string; status: string; label: string; danger?: boolean }) {
  return (
    <form action={setBookingStatus}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="status" value={status} />
      <button className={`act${danger ? " danger" : ""}`}>{label}</button>
    </form>
  );
}

export default async function BookingsPage() {
  const { tenant } = await requireTenant();
  await expireHolds(tenant.id);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const rows = await db
    .select({ b: bookings, service: services.name, staffName: staff.displayName, customer: customers.name, phone: customers.phone })
    .from(bookings)
    .innerJoin(services, eq(bookings.serviceId, services.id))
    .innerJoin(staff, eq(bookings.staffId, staff.id))
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .where(and(eq(bookings.tenantId, tenant.id), gte(bookings.startsAt, since)))
    .orderBy(asc(bookings.startsAt))
    .limit(100);

  const groups: { day: string; items: typeof rows }[] = [];
  for (const r of rows) {
    const day = formatDay(r.b.startsAt, tenant.timezone);
    const last = groups[groups.length - 1];
    if (last?.day === day) last.items.push(r);
    else groups.push({ day, items: [r] });
  }

  return (
    <>
      <PageHead title="Bookings" sub="Upcoming appointments and the last 24 hours." />

      {groups.length === 0 ? (
        <section className="glass panel enter" style={num(1)}>
          <p className="muted empty-state">No bookings yet. They will show up here as soon as a customer books.</p>
        </section>
      ) : (
        groups.map((g, gi) => (
          <section key={g.day} className="glass panel enter" style={num(gi + 1)}>
            <h2 className="day-head">{g.day}</h2>
            <ul className="list">
              {g.items.map((r) => (
                <BookingCard
                  key={r.b.id}
                  b={r.b}
                  service={r.service}
                  staffName={r.staffName}
                  customer={r.customer}
                  phone={r.phone}
                  tz={tenant.timezone}
                  actions={
                    r.b.status === "confirmed" || r.b.status === "pending" ? (
                      <>
                        {r.b.status === "confirmed" && <Action id={r.b.id} status="completed" label="Mark completed" />}
                        {r.b.status === "confirmed" && <Action id={r.b.id} status="no_show" label="No-show" />}
                        <Action id={r.b.id} status="cancelled" label="Cancel" danger />
                      </>
                    ) : undefined
                  }
                />
              ))}
            </ul>
          </section>
        ))
      )}
    </>
  );
}
EOF

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
