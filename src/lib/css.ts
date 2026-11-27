import type { CSSProperties } from "react";

// stagger index for entrance animations
export const num = (i: number) => ({ "--i": i }) as CSSProperties;
export const hueVar = (h: number) => ({ "--ah": h }) as CSSProperties;
export const statusHue = (h: number) => ({ "--s": h }) as CSSProperties;
