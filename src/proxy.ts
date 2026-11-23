import { NextRequest, NextResponse } from "next/server";

const ROOT = (process.env.NEXT_PUBLIC_ROOT_DOMAIN ?? "").split(":")[0];

export function proxy(req: NextRequest) {
  if (!ROOT) return NextResponse.next();

  const hostname = (req.headers.get("host") ?? "").split(":")[0];
  const sub = hostname.endsWith(`.${ROOT}`)
    ? hostname.slice(0, -(ROOT.length + 1))
    : null;

  if (!sub || sub === "www") return NextResponse.next();

  const url = req.nextUrl.clone();
  url.pathname =
    sub === "app" ? `/dashboard${url.pathname}` : `/sites/${sub}${url.pathname}`;
  return NextResponse.rewrite(url);
}

export const config = {
  matcher: ["/((?!api|_next|_static|.*\\..*).*)"],
};
