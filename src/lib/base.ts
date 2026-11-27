import { headers } from "next/headers";

// "" on a tenant subdomain, "/b/<slug>" when served in path mode.
export async function basePath() {
  const v = (await headers()).get("x-base") ?? "";
  return /^\/b\/[a-z0-9-]+$/.test(v) ? v : "";
}
