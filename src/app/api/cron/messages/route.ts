import { timingSafeEqual } from "node:crypto";
import { processDueMessages } from "@/lib/messaging";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function authorised(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const sent = Buffer.from(req.headers.get("authorization") ?? "");
  const want = Buffer.from(`Bearer ${secret}`);
  return sent.length === want.length && timingSafeEqual(sent, want);
}

async function run(req: Request) {
  if (!authorised(req)) return new Response("Unauthorized", { status: 401 });
  return Response.json(await processDueMessages());
}

export const GET = run;
export const POST = run;
