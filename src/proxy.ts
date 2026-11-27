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
