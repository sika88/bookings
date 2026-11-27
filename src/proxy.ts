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

  // a business's public booking page
  if (sub && sub !== "app") {
    const url = req.nextUrl.clone();
    url.pathname = `/sites/${sub}${pathname}`;
    return NextResponse.rewrite(url);
  }

  // app.<root>, or any other host such as *.vercel.app: the dashboard
  const url = req.nextUrl.clone();
  url.pathname = `/dashboard${pathname}`;
  return NextResponse.rewrite(url);
}

export const config = {
  matcher: ["/((?!api|_next|_static|.*\\..*).*)"],
};
