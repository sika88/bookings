import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { nextCookies } from "better-auth/next-js";
import { db } from "../db";
import * as schema from "../db/schema";

const root = process.env.NEXT_PUBLIC_ROOT_DOMAIN!;
const proto = process.env.NODE_ENV === "production" ? "https" : "http";

// Vercel exposes its own hostnames, so the *.vercel.app address can sign in too.
const vercelOrigins = [
  process.env.VERCEL_PROJECT_PRODUCTION_URL,
  process.env.VERCEL_URL,
  process.env.VERCEL_BRANCH_URL,
]
  .filter((h): h is string => !!h)
  .map((h) => `https://${h}`);

export const auth = betterAuth({
  database: drizzleAdapter(db, { provider: "pg", schema }),
  emailAndPassword: { enabled: true },
  trustedOrigins: [`${proto}://${root}`, `${proto}://app.${root}`, ...vercelOrigins],
  plugins: [nextCookies()],
});
