#!/usr/bin/env bash
set -e

mkdir -p src/lib \
  "src/app/sites/[tenant]/book" \
  "src/app/sites/[tenant]/booking/[token]"

# ---------- shared ----------
cat > src/lib/hue.ts <<'EOF'
// Stable colour hue (0-359) from any string, used to theme each business.
export function hueOf(s: string) {
  let h = 7;
  for (const c of s) h = (h * 31 + c.charCodeAt(0)) % 360;
  return h;
}
EOF

cat > "src/app/sites/[tenant]/glass.css" <<'EOF'
/* Public booking site: glass theme. Colours derive from --h, a hue set per business. */

.glass-root {
  --h: 250;
  --ink: #090d1c;
  --text: #f4f6ff;
  --muted: rgba(224, 229, 255, 0.66);
  --line: rgba(255, 255, 255, 0.16);
  --line-strong: rgba(255, 255, 255, 0.32);
  --accent: hsl(var(--h) 96% 70%);
  --accent-2: hsl(calc(var(--h) + 55) 96% 68%);
  position: relative;
  isolation: isolate;
  min-height: 100vh;
  color: var(--text);
  background: var(--ink);
  font-family: var(--font-body), ui-sans-serif, system-ui, sans-serif;
  overflow-x: clip;
  -webkit-font-smoothing: antialiased;
}

.glass-root a:focus-visible,
.glass-root button:focus-visible,
.glass-root input:focus-visible,
.glass-root textarea:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 3px;
}

/* ---------- background ---------- */
.aurora { position: fixed; inset: 0; z-index: -1; overflow: hidden; pointer-events: none; }
.aurora i { position: absolute; border-radius: 50%; opacity: 0.6; will-change: transform; }
.aurora i:nth-of-type(1) {
  width: 60vmax; height: 60vmax; left: -18vmax; top: -22vmax;
  background: radial-gradient(circle at 35% 35%, hsl(var(--h) 95% 58%), transparent 66%);
  animation: drift-a 34s ease-in-out infinite;
}
.aurora i:nth-of-type(2) {
  width: 55vmax; height: 55vmax; right: -20vmax; top: 6vmax;
  background: radial-gradient(circle at 60% 40%, hsl(calc(var(--h) + 55) 95% 56%), transparent 66%);
  animation: drift-b 40s ease-in-out infinite;
}
.aurora i:nth-of-type(3) {
  width: 52vmax; height: 52vmax; left: 12vmax; bottom: -28vmax;
  background: radial-gradient(circle, hsl(calc(var(--h) - 60) 90% 55%), transparent 66%);
  animation: drift-c 46s ease-in-out infinite;
}
/* crisp orbs give the glass something to refract */
.aurora b {
  position: absolute; border-radius: 50%;
  background: radial-gradient(circle at 30% 25%, rgba(255, 255, 255, 0.85), hsl(var(--h) 95% 62%) 38%, hsl(calc(var(--h) + 55) 90% 42%) 100%);
  box-shadow: 0 30px 80px hsl(var(--h) 90% 50% / 0.45);
}
.aurora b:nth-of-type(1) { width: 14rem; height: 14rem; left: 5%; top: 50%; animation: bob-a 18s ease-in-out infinite; }
.aurora b:nth-of-type(2) { width: 9rem; height: 9rem; right: 10%; top: 12%; animation: bob-b 22s ease-in-out infinite;
  background: radial-gradient(circle at 30% 25%, rgba(255, 255, 255, 0.85), hsl(calc(var(--h) + 55) 95% 62%) 40%, hsl(calc(var(--h) + 110) 90% 42%) 100%); }
.aurora b:nth-of-type(3) { width: 6rem; height: 6rem; right: 28%; bottom: 8%; animation: bob-c 16s ease-in-out infinite; }
@media (max-width: 640px) {
  .aurora b:nth-of-type(1) { width: 9rem; height: 9rem; }
  .aurora b:nth-of-type(2) { width: 6rem; height: 6rem; }
}

/* ---------- layout ---------- */
.shell { max-width: 72rem; margin: 0 auto; padding: 1.25rem; display: grid; gap: 1.25rem; }
.steps { display: grid; gap: 1.25rem; min-width: 0; }
.shell-narrow { max-width: 30rem; margin: 0 auto; padding: 1.5rem 1.25rem 3rem; display: grid; gap: 1.25rem; }
@media (min-width: 1024px) {
  .shell { grid-template-columns: 22rem minmax(0, 1fr); gap: 1.75rem; padding: 3rem 2rem; align-items: start; }
  .ticket { position: sticky; top: 2rem; }
}

/* ---------- glass ---------- */
.glass {
  position: relative;
  background: linear-gradient(135deg, rgba(255, 255, 255, 0.14), rgba(255, 255, 255, 0.05));
  -webkit-backdrop-filter: blur(26px) saturate(170%);
  backdrop-filter: blur(26px) saturate(170%);
  border: 1px solid var(--line);
  border-radius: 28px;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), inset 0 -1px 0 rgba(255, 255, 255, 0.04), 0 30px 80px -30px rgba(0, 0, 0, 0.65);
}
@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .glass { background: rgba(22, 26, 52, 0.88); }
}
.panel { padding: 1.5rem; }
.step { padding: 1.5rem; }
@media (min-width: 640px) { .step, .panel { padding: 1.75rem; } }

/* ---------- type ---------- */
.display { font-family: var(--font-display), var(--font-body), sans-serif; font-weight: 700; letter-spacing: -0.035em; }
.brand { font-size: clamp(2.3rem, 5vw, 3.3rem); line-height: 0.95; margin-top: 1.25rem; overflow-wrap: anywhere; }
.h-md { font-size: 1.9rem; line-height: 1; margin-bottom: 1.25rem; overflow-wrap: anywhere; }
.muted { color: var(--muted); }
.small { font-size: 0.85rem; }
.lead { margin-top: 0.75rem; line-height: 1.5; max-width: 28ch; }

.monogram {
  width: 3.25rem; height: 3.25rem; border-radius: 16px; display: grid; place-items: center;
  font-family: var(--font-display), sans-serif; font-weight: 700; font-size: 1.6rem; color: var(--ink);
  background: linear-gradient(135deg, var(--accent), var(--accent-2));
  box-shadow: 0 10px 30px -8px hsl(var(--h) 100% 60% / 0.8), inset 0 1px 0 rgba(255, 255, 255, 0.5);
}

/* ---------- booking summary (left panel) ---------- */
.ticket { padding: 1.75rem; }
.rows { margin-top: 1.75rem; display: grid; gap: 1.2rem; }
.row { position: relative; padding-left: 1.7rem; }
.row::before {
  content: ""; position: absolute; left: 0; top: 0.35rem; width: 0.7rem; height: 0.7rem; border-radius: 50%;
  border: 1.5px solid var(--line-strong); transition: background 0.3s, border-color 0.3s, box-shadow 0.3s;
}
.row:not(:last-child)::after { content: ""; position: absolute; left: 0.35rem; top: 1.2rem; bottom: -1.2rem; width: 1px; background: var(--line); }
.row.done::before { background: var(--accent); border-color: transparent; box-shadow: 0 0 14px hsl(var(--h) 100% 65% / 0.8); }
.row.next::before { border-color: var(--accent); animation: pulse-ring 1.8s ease-out infinite; }
.row dt { font-size: 0.82rem; color: var(--muted); }
.row dd { margin: 0.1rem 0 0; display: flex; flex-direction: column; font-size: 1.05rem; font-weight: 500; }
.row.idle dd > span:first-child { color: var(--muted); font-weight: 400; }
.swap { animation: swap 0.4s cubic-bezier(0.2, 0.8, 0.2, 1) both; }
.note {
  margin-top: 1.5rem; padding: 0.9rem 1rem; border-radius: 16px; font-size: 0.9rem; line-height: 1.45;
  background: hsl(var(--h) 95% 65% / 0.14); border: 1px solid hsl(var(--h) 100% 78% / 0.35);
}

/* ---------- steps ---------- */
.step-head { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1.1rem; }
.step-head h2 { font-family: var(--font-display), sans-serif; font-weight: 600; font-size: 1.3rem; letter-spacing: -0.02em; }
.step-head .muted { margin-left: auto; font-size: 0.85rem; }
.badge {
  width: 1.75rem; height: 1.75rem; border-radius: 999px; display: grid; place-items: center; flex: none;
  font-size: 0.8rem; font-weight: 600; border: 1px solid var(--line-strong); transition: background 0.3s;
}
.badge.done { background: var(--accent); color: var(--ink); border-color: transparent; }

.tile {
  position: relative; display: block; border-radius: 18px; background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line);
  transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1), background 0.25s, border-color 0.25s, box-shadow 0.25s;
}
.tile:hover { transform: translateY(-2px); background: rgba(255, 255, 255, 0.11); border-color: var(--line-strong); }
.tile:active { transform: scale(0.985); }
.is-active {
  background: linear-gradient(135deg, hsl(var(--h) 95% 62% / 0.32), hsl(calc(var(--h) + 55) 95% 60% / 0.22)) !important;
  border-color: hsl(var(--h) 100% 78% / 0.75) !important;
  box-shadow: 0 0 0 1px hsl(var(--h) 100% 78% / 0.3), 0 18px 50px -18px hsl(var(--h) 100% 60% / 0.8);
}

.services { display: grid; gap: 0.75rem; }
@media (min-width: 640px) { .services { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
.service { padding: 1.1rem 3rem 1.1rem 1.1rem; }
.service-name { font-family: var(--font-display), sans-serif; font-weight: 600; font-size: 1.15rem; letter-spacing: -0.02em; }
.service p { margin-top: 0.3rem; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.pills { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.8rem; }
.pill { padding: 0.2rem 0.65rem; border-radius: 999px; font-size: 0.78rem; background: rgba(255, 255, 255, 0.1); border: 1px solid var(--line); }
.pill.accent { background: hsl(var(--h) 95% 65% / 0.2); border-color: hsl(var(--h) 100% 78% / 0.5); }
.tick {
  position: absolute; top: 1rem; right: 1rem; width: 1.6rem; height: 1.6rem; border-radius: 50%; display: grid; place-items: center;
  background: var(--accent); color: var(--ink); transform: scale(0); font-size: 0.9rem;
}
.is-active .tick { animation: pop-in 0.45s cubic-bezier(0.3, 1.6, 0.5, 1) forwards; }

.whos { display: flex; flex-wrap: wrap; gap: 0.6rem; }
.who {
  position: relative; display: inline-flex; align-items: center; gap: 0.6rem; padding: 0.4rem 1rem 0.4rem 0.4rem; border-radius: 999px;
  background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line); font-weight: 500;
  transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1), background 0.25s, border-color 0.25s;
}
.who:hover { transform: translateY(-2px); background: rgba(255, 255, 255, 0.11); }
.who:active { transform: scale(0.97); }
.avatar {
  width: 2rem; height: 2rem; border-radius: 50%; display: grid; place-items: center; font-weight: 700; font-size: 0.9rem; color: var(--ink);
  background: linear-gradient(135deg, hsl(var(--ah, 200) 90% 68%), hsl(calc(var(--ah, 200) + 40) 90% 62%));
}
.avatar.any { background: rgba(255, 255, 255, 0.16); color: var(--text); }

.days { display: flex; gap: 0.6rem; overflow-x: auto; padding: 0.35rem 0.25rem 1rem; margin: -0.35rem -0.25rem 0; scroll-snap-type: x proximity; scrollbar-width: thin; }
.day {
  position: relative; flex: 0 0 4.6rem; display: grid; justify-items: center; gap: 0.05rem; padding: 0.75rem 0; border-radius: 18px;
  scroll-snap-align: start; background: rgba(255, 255, 255, 0.07); border: 1px solid var(--line);
  transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1), background 0.25s, border-color 0.25s, box-shadow 0.25s;
}
.day:hover { transform: translateY(-2px); background: rgba(255, 255, 255, 0.11); }
.day:active { transform: scale(0.97); }
.day-name { font-size: 0.78rem; color: var(--muted); }
.day-num { font-family: var(--font-display), sans-serif; font-weight: 700; font-size: 1.6rem; line-height: 1.1; letter-spacing: -0.03em; }
.day-mon { font-size: 0.78rem; color: var(--muted); }
.day.is-active .day-name, .day.is-active .day-mon { color: var(--text); }

.group-title { margin: 1.3rem 0 0.6rem; font-size: 0.9rem; color: var(--muted); display: flex; justify-content: space-between; }
.group-title:first-of-type { margin-top: 0.25rem; }
.slots { display: grid; grid-template-columns: repeat(auto-fill, minmax(5.2rem, 1fr)); gap: 0.6rem; }
.slot {
  position: relative; display: block; text-align: center; padding: 0.7rem 0; border-radius: 999px; font-weight: 500; font-variant-numeric: tabular-nums;
  background: rgba(255, 255, 255, 0.08); border: 1px solid var(--line);
  transition: transform 0.2s cubic-bezier(0.2, 0.8, 0.2, 1), background 0.2s, color 0.2s, box-shadow 0.2s, border-color 0.2s;
}
.slot:hover {
  transform: translateY(-2px); color: var(--ink); border-color: transparent;
  background: linear-gradient(120deg, var(--accent), var(--accent-2)); box-shadow: 0 12px 28px -10px hsl(var(--h) 100% 60% / 0.9);
}
.slot:active { transform: scale(0.96); }
.empty { padding: 1.5rem 0.25rem; line-height: 1.5; }

/* ---------- link loading shimmer ---------- */
.pending {
  position: absolute; inset: 0; border-radius: inherit; pointer-events: none; opacity: 0;
  background: linear-gradient(100deg, transparent 20%, rgba(255, 255, 255, 0.28) 50%, transparent 80%); background-size: 200% 100%;
}
.pending.on { opacity: 1; animation: sweep 0.9s linear infinite; }

/* ---------- forms and buttons ---------- */
.summary { display: grid; gap: 0.7rem; margin-bottom: 1.25rem; padding-bottom: 1.25rem; border-bottom: 1px solid var(--line); }
.summary > div { display: flex; justify-content: space-between; gap: 1rem; }
.summary dt { color: var(--muted); font-size: 0.9rem; }
.summary dd { font-weight: 500; text-align: right; }
.back { display: inline-flex; align-items: center; gap: 0.35rem; font-size: 0.9rem; color: var(--muted); width: fit-content; padding: 0.4rem 0.8rem 0.4rem 0.5rem; border-radius: 999px; border: 1px solid var(--line); background: rgba(255, 255, 255, 0.06); transition: color 0.2s, background 0.2s; }
.back:hover { color: var(--text); background: rgba(255, 255, 255, 0.12); }
.form { display: grid; gap: 0.9rem; margin-top: 1.25rem; }
.form label { display: grid; gap: 0.35rem; font-size: 0.85rem; color: var(--muted); }
.field {
  width: 100%; padding: 0.8rem 0.95rem; border-radius: 14px; color: var(--text); font: inherit; font-size: 1rem;
  background: rgba(255, 255, 255, 0.08); border: 1px solid var(--line); transition: border-color 0.2s, background 0.2s;
}
.field::placeholder { color: rgba(224, 229, 255, 0.38); }
.field:focus { background: rgba(255, 255, 255, 0.12); border-color: hsl(var(--h) 100% 78% / 0.8); outline: none; }
.btn {
  display: block; width: 100%; padding: 0.95rem 1.25rem; border-radius: 999px; border: 0; text-align: center; font: inherit; font-weight: 600; font-size: 1rem;
  color: var(--ink); cursor: pointer; background: linear-gradient(120deg, var(--accent), var(--accent-2));
  box-shadow: 0 14px 34px -12px hsl(var(--h) 100% 60% / 0.9), inset 0 1px 0 rgba(255, 255, 255, 0.5);
  transition: transform 0.2s, filter 0.2s, box-shadow 0.2s;
}
.btn:hover { transform: translateY(-1px); filter: brightness(1.06); }
.btn:active { transform: scale(0.985); }
.btn:disabled { opacity: 0.5; cursor: not-allowed; transform: none; filter: none; }
.btn-danger { background: transparent; color: #ffb4b4; border: 1px solid rgba(255, 130, 130, 0.5); box-shadow: none; }
.alert { padding: 0.8rem 1rem; border-radius: 14px; font-size: 0.9rem; background: rgba(255, 90, 90, 0.14); border: 1px solid rgba(255, 130, 130, 0.45); color: #ffd0d0; }

/* ---------- booking status ---------- */
.status-icon {
  width: 4rem; height: 4rem; border-radius: 50%; display: grid; place-items: center; font-size: 1.8rem; margin-bottom: 1rem;
  background: hsl(var(--s) 90% 60% / 0.18); border: 1px solid hsl(var(--s) 100% 75% / 0.55); color: hsl(var(--s) 100% 78%);
  box-shadow: 0 0 40px hsl(var(--s) 100% 60% / 0.4); animation: pop-in 0.6s cubic-bezier(0.3, 1.5, 0.5, 1) both;
}
.timer { font-family: var(--font-display), sans-serif; font-size: 2.6rem; font-weight: 700; letter-spacing: -0.03em; font-variant-numeric: tabular-nums; line-height: 1; }
.bar { height: 6px; border-radius: 99px; background: rgba(255, 255, 255, 0.12); overflow: hidden; margin-top: 0.8rem; }
.bar > i { display: block; height: 100%; background: linear-gradient(90deg, var(--accent), var(--accent-2)); transition: width 1s linear; }
.draw path { stroke-dasharray: 1; stroke-dashoffset: 1; animation: draw 0.5s 0.25s ease forwards; }

/* ---------- motion ---------- */
.enter { animation: frost 0.9s cubic-bezier(0.2, 0.8, 0.2, 1) both; animation-delay: calc(var(--i, 0) * 90ms); }
.pop { animation: pop 0.4s cubic-bezier(0.2, 0.9, 0.3, 1.2) both; animation-delay: calc(var(--i, 0) * 22ms); }

@keyframes frost {
  from { opacity: 0; transform: translateY(10px) scale(0.99); -webkit-backdrop-filter: blur(0) saturate(100%); backdrop-filter: blur(0) saturate(100%); }
  to { opacity: 1; transform: none; -webkit-backdrop-filter: blur(26px) saturate(170%); backdrop-filter: blur(26px) saturate(170%); }
}
@keyframes pop { from { opacity: 0; transform: scale(0.9) translateY(6px); } to { opacity: 1; transform: none; } }
@keyframes pop-in { from { transform: scale(0); } to { transform: scale(1); } }
@keyframes swap { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
@keyframes draw { to { stroke-dashoffset: 0; } }
@keyframes sweep { from { background-position: 200% 0; } to { background-position: -200% 0; } }
@keyframes pulse-ring {
  0% { box-shadow: 0 0 0 0 hsl(var(--h) 100% 70% / 0.6); }
  100% { box-shadow: 0 0 0 0.6rem hsl(var(--h) 100% 70% / 0); }
}
@keyframes drift-a { 0%, 100% { transform: translate3d(0, 0, 0) scale(1); } 50% { transform: translate3d(10vw, 8vh, 0) scale(1.15); } }
@keyframes drift-b { 0%, 100% { transform: translate3d(0, 0, 0) scale(1.05); } 50% { transform: translate3d(-12vw, 6vh, 0) scale(0.92); } }
@keyframes drift-c { 0%, 100% { transform: translate3d(0, 0, 0) scale(1); } 50% { transform: translate3d(8vw, -10vh, 0) scale(1.2); } }
@keyframes bob-a { 0%, 100% { transform: translate3d(0, 0, 0); } 50% { transform: translate3d(3vw, -6vh, 0); } }
@keyframes bob-b { 0%, 100% { transform: translate3d(0, 0, 0); } 50% { transform: translate3d(-4vw, 5vh, 0); } }
@keyframes bob-c { 0%, 100% { transform: translate3d(0, 0, 0); } 50% { transform: translate3d(5vw, 4vh, 0); } }

@media (prefers-reduced-motion: reduce) {
  .glass-root *, .glass-root *::before, .glass-root *::after { animation: none !important; transition: none !important; }
  .tick { transform: scale(1) !important; }
  .draw path { stroke-dashoffset: 0; }
}
EOF

cat > "src/app/sites/[tenant]/layout.tsx" <<'EOF'
import type { CSSProperties } from "react";
import type { Metadata } from "next";
import { Bricolage_Grotesque, Instrument_Sans } from "next/font/google";
import { getTenantBySlug } from "@/lib/tenant";
import { hueOf } from "@/lib/hue";
import "./glass.css";

const display = Bricolage_Grotesque({ subsets: ["latin"], variable: "--font-display", display: "swap" });
const body = Instrument_Sans({ subsets: ["latin"], variable: "--font-body", display: "swap" });

export async function generateMetadata({ params }: { params: Promise<{ tenant: string }> }): Promise<Metadata> {
  const { tenant: slug } = await params;
  const tenant = await getTenantBySlug(slug);
  return { title: tenant ? `Book at ${tenant.name}` : "Not found" };
}

export default async function SiteLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ tenant: string }>;
}) {
  const { tenant: slug } = await params;

  return (
    <div
      className={`${display.variable} ${body.variable} glass-root`}
      style={{ "--h": hueOf(slug) } as CSSProperties}
    >
      <div className="aurora" aria-hidden="true">
        <i /><i /><i />
        <b /><b /><b />
      </div>
      {children}
    </div>
  );
}
EOF

cat > "src/app/sites/[tenant]/icons.tsx" <<'EOF'
const base = {
  viewBox: "0 0 16 16",
  width: "1em",
  height: "1em",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

export function Check() {
  return (
    <svg {...base} className="draw">
      <path pathLength={1} d="M3.5 8.5l3 3 6-7" />
    </svg>
  );
}

export function Cross() {
  return (
    <svg {...base} className="draw">
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
EOF

cat > "src/app/sites/[tenant]/pending.tsx" <<'EOF'
"use client";

import { useLinkStatus } from "next/link";

// Render inside a <Link>: shows a shimmer while that link's page is loading.
export default function Pending() {
  const { pending } = useLinkStatus();
  return <span aria-hidden="true" className={`pending${pending ? " on" : ""}`} />;
}
EOF

# ---------- booking page ----------
cat > "src/app/sites/[tenant]/page.tsx" <<'EOF'
import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, asc, eq } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { addDays, format } from "date-fns";
import { db } from "@/db";
import { services, staff, staffServices } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";
import { depositFor } from "@/lib/bookings";
import { hueOf } from "@/lib/hue";
import { formatMoney } from "@/lib/money";
import { Check, Users } from "./icons";
import Pending from "./pending";

type SP = { service?: string; staff?: string; date?: string };

const num = (i: number) => ({ "--i": i }) as CSSProperties;
const hueVar = (h: number) => ({ "--ah": h }) as CSSProperties;

function href(p: SP) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(p)) if (v) q.set(k, v);
  return `?${q.toString()}`;
}

const hourOf = (label: string) => parseInt(label.slice(0, 2), 10);

function Row({ label, value, sub, state }: { label: string; value: string; sub?: string; state: "done" | "next" | "idle" }) {
  return (
    <div className={`row ${state}`}>
      <dt>{label}</dt>
      <dd>
        <span key={value} className="swap">{value}</span>
        {sub && <span className="muted small">{sub}</span>}
      </dd>
    </div>
  );
}

function StepHead({ n, title, done, hint }: { n: number; title: string; done?: boolean; hint?: string }) {
  return (
    <div className="step-head">
      <span className={`badge${done ? " done" : ""}`}>{done ? <Check /> : n}</span>
      <h2>{title}</h2>
      {hint && <span className="muted">{hint}</span>}
    </div>
  );
}

export default async function TenantHome({
  params,
  searchParams,
}: {
  params: Promise<{ tenant: string }>;
  searchParams: Promise<SP>;
}) {
  const { tenant: slug } = await params;
  const sp = await searchParams;
  const tenant = await getTenantBySlug(slug);
  if (!tenant) notFound();

  const allServices = await db
    .select()
    .from(services)
    .where(and(eq(services.tenantId, tenant.id), eq(services.active, true)))
    .orderBy(asc(services.name));

  const service = allServices.find((s) => s.id === sp.service);

  let people: { id: string; displayName: string }[] = [];
  if (service) {
    people = await db
      .select({ id: staff.id, displayName: staff.displayName })
      .from(staffServices)
      .innerJoin(staff, eq(staff.id, staffServices.staffId))
      .where(and(eq(staffServices.serviceId, service.id), eq(staff.active, true), eq(staff.tenantId, tenant.id)))
      .orderBy(asc(staff.displayName));
  }
  const chosenStaff = people.find((p) => p.id === sp.staff);

  const today = TZDate.tz(tenant.timezone);
  const days = Array.from({ length: 14 }, (_, i) => {
    const d = addDays(today, i);
    return {
      value: format(d, "yyyy-MM-dd"),
      weekday: i === 0 ? "Today" : format(d, "EEE"),
      num: format(d, "d"),
      month: format(d, "MMM"),
      full: format(d, "EEEE d MMMM"),
    };
  });
  const day = days.find((d) => d.value === sp.date) ?? days[0];

  const slots = service
    ? await getSlots({ tenant, serviceId: service.id, staffId: chosenStaff?.id, date: day.value })
    : [];

  const slotHref = (start: string) => {
    const q = new URLSearchParams({ service: service!.id, start });
    if (chosenStaff) q.set("staff", chosenStaff.id);
    return `/book?${q.toString()}`;
  };

  const groups = [
    { title: "Morning", items: slots.filter((s) => hourOf(s.label) < 12) },
    { title: "Afternoon", items: slots.filter((s) => hourOf(s.label) >= 12 && hourOf(s.label) < 17) },
    { title: "Evening", items: slots.filter((s) => hourOf(s.label) >= 17) },
  ].filter((g) => g.items.length > 0);
  let n = 0;

  const deposit = service ? depositFor(service) : 0;

  return (
    <main className="shell">
      <aside className="glass ticket enter" style={num(0)}>
        <div className="monogram">{tenant.name.charAt(0).toUpperCase()}</div>
        <h1 className="display brand">{tenant.name}</h1>
        <p className="muted lead">Pick a service, then a day and time. Your booking takes shape here.</p>

        <dl className="rows">
          <Row
            label="Service"
            value={service ? service.name : "Choose a service"}
            sub={service ? `${service.durationMin} min, ${formatMoney(service.pricePesewas)}` : undefined}
            state={service ? "done" : "next"}
          />
          <Row
            label="With"
            value={service ? (chosenStaff?.displayName ?? "Any available") : "Not chosen yet"}
            state={service ? "done" : "idle"}
          />
          <Row
            label="Day"
            value={service ? day.full : "Not chosen yet"}
            sub={service ? (slots.length ? `${slots.length} times open` : "Fully booked") : undefined}
            state={service ? "done" : "idle"}
          />
          <Row label="Time" value={service ? "Pick a time" : "Not chosen yet"} state={service ? "next" : "idle"} />
        </dl>

        {service && deposit > 0 && (
          <p className="note">
            A deposit of {formatMoney(deposit)} holds your slot for 10 minutes. Pay it with Mobile Money to confirm.
          </p>
        )}
      </aside>

      <div className="steps">
        <section className="glass step enter" style={num(1)}>
          <StepHead n={1} title="Choose a service" done={!!service} />
          {allServices.length === 0 ? (
            <p className="muted empty">This business has not added any services yet. Please check back soon.</p>
          ) : (
            <div className="services">
              {allServices.map((s, i) => (
                <Link
                  key={s.id}
                  href={href({ service: s.id })}
                  aria-current={service?.id === s.id ? "true" : undefined}
                  className={`tile service pop${service?.id === s.id ? " is-active" : ""}`}
                  style={num(i)}
                >
                  <div className="service-name">{s.name}</div>
                  {s.description && <p className="muted small">{s.description}</p>}
                  <div className="pills">
                    <span className="pill">{s.durationMin} min</span>
                    <span className="pill">{formatMoney(s.pricePesewas)}</span>
                    {s.depositType !== "none" && (
                      <span className="pill accent">
                        {s.depositType === "fixed" ? `${formatMoney(s.depositValue)} deposit` : `${s.depositValue}% deposit`}
                      </span>
                    )}
                  </div>
                  <span className="tick"><Check /></span>
                  <Pending />
                </Link>
              ))}
            </div>
          )}
        </section>

        {service && (
          <section className="glass step enter" style={num(0)}>
            <StepHead n={2} title="Who do you want to see?" done />
            <div className="whos">
              <Link
                href={href({ service: service.id, date: day.value })}
                aria-current={!chosenStaff ? "true" : undefined}
                className={`who pop${!chosenStaff ? " is-active" : ""}`}
                style={num(0)}
              >
                <span className="avatar any"><Users /></span>
                Any available
                <Pending />
              </Link>
              {people.map((p, i) => (
                <Link
                  key={p.id}
                  href={href({ service: service.id, staff: p.id, date: day.value })}
                  aria-current={chosenStaff?.id === p.id ? "true" : undefined}
                  className={`who pop${chosenStaff?.id === p.id ? " is-active" : ""}`}
                  style={num(i + 1)}
                >
                  <span className="avatar" style={hueVar(hueOf(p.displayName))}>{p.displayName.charAt(0).toUpperCase()}</span>
                  {p.displayName}
                  <Pending />
                </Link>
              ))}
            </div>
          </section>
        )}

        {service && (
          <section className="glass step enter" style={num(1)}>
            <StepHead n={3} title="Choose a day" done />
            <div className="days">
              {days.map((d, i) => (
                <Link
                  key={d.value}
                  href={href({ service: service.id, staff: chosenStaff?.id, date: d.value })}
                  aria-current={d.value === day.value ? "date" : undefined}
                  className={`day pop${d.value === day.value ? " is-active" : ""}`}
                  style={num(i)}
                >
                  <span className="day-name">{d.weekday}</span>
                  <span className="day-num">{d.num}</span>
                  <span className="day-mon">{d.month}</span>
                  <Pending />
                </Link>
              ))}
            </div>
          </section>
        )}

        {service && (
          <section className="glass step enter" style={num(2)}>
            <StepHead n={4} title="Pick a time" hint={day.full} />
            {groups.length === 0 ? (
              <p className="muted empty">
                No times are open on this day. Try another day, or choose a different person.
              </p>
            ) : (
              groups.map((g) => (
                <div key={g.title}>
                  <div className="group-title">
                    <span>{g.title}</span>
                    <span>{g.items.length} open</span>
                  </div>
                  <div className="slots">
                    {g.items.map((s) => (
                      <Link key={s.start} href={slotHref(s.start)} className="slot pop" style={num(Math.min(n++, 28))}>
                        {s.label}
                        <Pending />
                      </Link>
                    ))}
                  </div>
                </div>
              ))
            )}
          </section>
        )}
      </div>
    </main>
  );
}
EOF

# ---------- details form ----------
cat > "src/app/sites/[tenant]/book/booking-form.tsx" <<'EOF'
"use client";

import { useActionState } from "react";
import { createBooking } from "../actions";
import type { BookingState } from "../types";

export default function BookingForm({
  slug,
  serviceId,
  staffId,
  start,
  label,
}: {
  slug: string;
  serviceId: string;
  staffId?: string;
  start: string;
  label: string;
}) {
  const [state, action, pending] = useActionState<BookingState, FormData>(createBooking, undefined);
  const v = state?.values;

  return (
    <form action={action} className="form">
      <input type="hidden" name="slug" value={slug} />
      <input type="hidden" name="serviceId" value={serviceId} />
      {staffId && <input type="hidden" name="staffId" value={staffId} />}
      <input type="hidden" name="start" value={start} />

      <label>
        Your name
        <input name="name" required autoComplete="name" defaultValue={v?.name} className="field" />
      </label>
      <label>
        Phone number
        <input name="phone" type="tel" required autoComplete="tel" placeholder="024 123 4567" defaultValue={v?.phone} className="field" />
      </label>
      <label>
        Email (optional)
        <input name="email" type="email" autoComplete="email" defaultValue={v?.email} className="field" />
      </label>
      <label>
        Notes (optional)
        <textarea name="notes" rows={2} defaultValue={v?.notes} className="field" />
      </label>
      <p className="muted small">We will text your confirmation and reminders to this number.</p>

      {state?.error && <p className="alert" role="alert">{state.error}</p>}
      <button disabled={pending} className="btn">
        {pending ? "Booking..." : label}
      </button>
    </form>
  );
}
EOF

cat > "src/app/sites/[tenant]/book/page.tsx" <<'EOF'
import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { TZDate } from "@date-fns/tz";
import { format } from "date-fns";
import { db } from "@/db";
import { services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { getSlots } from "@/lib/slots";
import { depositFor } from "@/lib/bookings";
import { formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { isUuid } from "@/lib/ids";
import { Chevron } from "../icons";
import BookingForm from "./booking-form";

type SP = { service?: string; staff?: string; start?: string };

const num = (i: number) => ({ "--i": i }) as CSSProperties;

export default async function BookPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenant: string }>;
  searchParams: Promise<SP>;
}) {
  const { tenant: slug } = await params;
  const sp = await searchParams;
  const tenant = await getTenantBySlug(slug);
  if (!tenant) notFound();

  const startMs = Date.parse(sp.start ?? "");
  if (!sp.service || !isUuid(sp.service) || Number.isNaN(startMs)) notFound();
  const staffId = sp.staff && isUuid(sp.staff) ? sp.staff : undefined;

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, sp.service), eq(services.tenantId, tenant.id), eq(services.active, true)))
    .limit(1);
  if (!service) notFound();

  let staffName: string | null = null;
  if (staffId) {
    const [s] = await db
      .select({ name: staff.displayName })
      .from(staff)
      .where(and(eq(staff.id, staffId), eq(staff.tenantId, tenant.id)))
      .limit(1);
    staffName = s?.name ?? null;
  }

  const date = format(new TZDate(startMs, tenant.timezone), "yyyy-MM-dd");
  const slots = await getSlots({ tenant, serviceId: service.id, staffId, date });
  const stillFree = slots.some((s) => new Date(s.start).getTime() === startMs);

  const backQuery = new URLSearchParams({ service: service.id, date });
  if (staffId) backQuery.set("staff", staffId);
  const back = `/?${backQuery.toString()}`;

  const deposit = depositFor(service);

  return (
    <main className="shell-narrow">
      <Link href={back} className="back enter" style={num(0)}>
        <Chevron /> Back to times
      </Link>

      <section className="glass panel enter" style={num(1)}>
        <h1 className="display h-md">{tenant.name}</h1>

        {!stillFree ? (
          <div>
            <p className="display" style={{ fontSize: "1.3rem" }}>That time is no longer available</p>
            <p className="muted" style={{ marginTop: "0.4rem", lineHeight: 1.5 }}>
              Someone may have just booked it. Pick another time and you are set.
            </p>
            <Link href={back} className="btn" style={{ marginTop: "1.25rem" }}>Choose another time</Link>
          </div>
        ) : (
          <>
            <dl className="summary">
              <div><dt>Service</dt><dd>{service.name}</dd></div>
              <div><dt>With</dt><dd>{staffName ?? "First available"}</dd></div>
              <div><dt>When</dt><dd>{formatWhen(new Date(startMs), tenant.timezone)}</dd></div>
              <div><dt>Price</dt><dd>{formatMoney(service.pricePesewas)}</dd></div>
              {deposit > 0 && <div><dt>Deposit</dt><dd>{formatMoney(deposit)}</dd></div>}
            </dl>
            {deposit > 0 && (
              <p className="note" style={{ marginTop: 0 }}>
                Your time is held for 10 minutes after you continue. Pay the deposit with Mobile Money to confirm it.
              </p>
            )}
            <BookingForm
              slug={slug}
              serviceId={service.id}
              staffId={staffId}
              start={new Date(startMs).toISOString()}
              label={deposit > 0 ? "Hold my slot" : "Confirm booking"}
            />
          </>
        )}
      </section>
    </main>
  );
}
EOF

# ---------- booking status ----------
cat > "src/app/sites/[tenant]/booking/[token]/countdown.tsx" <<'EOF'
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

export default function Countdown({ initial, total }: { initial: number; total: number }) {
  const router = useRouter();
  const [left, setLeft] = useState(initial);

  useEffect(() => {
    const end = Date.now() + initial * 1000;
    const id = setInterval(() => {
      const s = Math.max(0, Math.ceil((end - Date.now()) / 1000));
      setLeft(s);
      if (s === 0) {
        clearInterval(id);
        router.refresh();
      }
    }, 1000);
    return () => clearInterval(id);
  }, [initial, router]);

  const mm = String(Math.floor(left / 60)).padStart(2, "0");
  const ss = String(left % 60).padStart(2, "0");

  return (
    <div role="timer" aria-live="off">
      <div className="timer">{mm}:{ss}</div>
      <div className="bar"><i style={{ width: `${Math.min(100, (left / total) * 100)}%` }} /></div>
    </div>
  );
}
EOF

cat > "src/app/sites/[tenant]/booking/[token]/page.tsx" <<'EOF'
import type { CSSProperties } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { bookings, customers, services, staff } from "@/db/schema";
import { getTenantBySlug } from "@/lib/tenant";
import { HOLD_MINUTES } from "@/lib/bookings";
import { formatTime, formatWhen } from "@/lib/format";
import { formatMoney } from "@/lib/money";
import { cancelBooking } from "../../actions";
import { Check, Clock, Cross } from "../../icons";
import Countdown from "./countdown";

const TOKEN = /^[a-f0-9]{32}$/;
const num = (i: number) => ({ "--i": i }) as CSSProperties;

export default async function BookingPage({
  params,
}: {
  params: Promise<{ tenant: string; token: string }>;
}) {
  const { tenant: slug, token } = await params;
  const tenant = await getTenantBySlug(slug);
  if (!tenant || !TOKEN.test(token)) notFound();

  const [row] = await db
    .select({
      booking: bookings,
      serviceName: services.name,
      staffName: staff.displayName,
      customerName: customers.name,
    })
    .from(bookings)
    .innerJoin(services, eq(bookings.serviceId, services.id))
    .innerJoin(staff, eq(bookings.staffId, staff.id))
    .innerJoin(customers, eq(bookings.customerId, customers.id))
    .where(and(eq(bookings.manageToken, token), eq(bookings.tenantId, tenant.id)))
    .limit(1);
  if (!row) notFound();

  const b = row.booking;
  const now = Date.now();
  const holdActive = b.status === "pending" && !!b.holdExpiresAt && b.holdExpiresAt.getTime() > now;
  const holdExpired = b.status === "pending" && !holdActive;
  const canCancel = (b.status === "confirmed" || holdActive) && b.startsAt.getTime() > now;

  let title = "";
  let message = "";
  let hue = 0;
  let icon: "check" | "clock" | "cross" = "cross";

  if (b.status === "confirmed") {
    title = "You are booked";
    message = "Keep this page. You can check or cancel your booking from it.";
    hue = 150;
    icon = "check";
  } else if (holdActive) {
    title = "Your slot is on hold";
    message = `Held until ${formatTime(b.holdExpiresAt!, tenant.timezone)}. Pay the ${formatMoney(b.depositPesewas)} deposit to confirm it.`;
    hue = 38;
    icon = "clock";
  } else if (holdExpired) {
    title = "This hold has expired";
    message = "The time was released because the deposit was not paid in time.";
  } else if (b.status === "cancelled") {
    title = "This booking was cancelled";
    message = "The time has been released.";
  } else if (b.status === "completed") {
    title = "Appointment completed";
    message = "Thank you for visiting.";
    hue = 200;
    icon = "check";
  } else {
    title = "Marked as a no-show";
  }

  return (
    <main className="shell-narrow">
      <section className="glass panel enter" style={{ ...num(0), "--s": hue } as CSSProperties}>
        <div className="status-icon">
          {icon === "check" ? <Check /> : icon === "clock" ? <Clock /> : <Cross />}
        </div>
        <h1 className="display h-md" style={{ marginBottom: "0.5rem" }}>{title}</h1>
        {message && <p className="muted" style={{ lineHeight: 1.5 }}>{message}</p>}

        {holdActive && (
          <div style={{ marginTop: "1.5rem" }}>
            <Countdown
              initial={Math.max(0, Math.ceil((b.holdExpiresAt!.getTime() - now) / 1000))}
              total={HOLD_MINUTES * 60}
            />
          </div>
        )}
      </section>

      <section className="glass panel enter" style={num(1)}>
        <p className="muted small" style={{ marginBottom: "0.9rem" }}>{tenant.name}</p>
        <dl className="summary" style={{ marginBottom: 0, paddingBottom: 0, borderBottom: 0 }}>
          <div><dt>Service</dt><dd>{row.serviceName}</dd></div>
          <div><dt>With</dt><dd>{row.staffName}</dd></div>
          <div><dt>When</dt><dd>{formatWhen(b.startsAt, tenant.timezone)}</dd></div>
          <div><dt>Booked for</dt><dd>{row.customerName}</dd></div>
          <div><dt>Total</dt><dd>{formatMoney(b.totalPesewas)}</dd></div>
          {b.depositPesewas > 0 && <div><dt>Deposit</dt><dd>{formatMoney(b.depositPesewas)}</dd></div>}
        </dl>
      </section>

      <div className="enter" style={{ ...num(2), display: "grid", gap: "0.75rem" }}>
        {holdActive && (
          <button disabled className="btn">Pay with Mobile Money (coming in the next step)</button>
        )}

        {canCancel && (
          <form action={cancelBooking}>
            <input type="hidden" name="slug" value={slug} />
            <input type="hidden" name="token" value={token} />
            <button className="btn btn-danger">Cancel this booking</button>
          </form>
        )}

        {(holdExpired || b.status === "cancelled") && (
          <Link href="/" className="btn">Book another time</Link>
        )}
      </div>
    </main>
  );
}
EOF

echo ""
echo "Done. Restart the dev server (Ctrl+C, then: npm run dev)"
