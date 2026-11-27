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
