// Pure helpers, safe to import from client components.
export const NETWORKS = { mtn: "MTN MoMo", vod: "Telecel Cash", atl: "AirtelTigo Money" } as const;
export type Network = keyof typeof NETWORKS;

export const isNetwork = (s: string): s is Network => s === "mtn" || s === "vod" || s === "atl";

export function guessNetwork(input: string): Network | null {
  const d = input.replace(/\D/g, "").replace(/^233/, "0");
  const p = d.slice(0, 3);
  if (["024", "025", "053", "054", "055", "059"].includes(p)) return "mtn";
  if (["020", "050"].includes(p)) return "vod";
  if (["026", "027", "056", "057"].includes(p)) return "atl";
  return null;
}

// +233241234567 -> 0241234567
export const toLocalPhone = (e164: string) => `0${e164.replace(/\D/g, "").slice(-9)}`;
