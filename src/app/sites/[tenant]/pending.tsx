"use client";

import { useLinkStatus } from "next/link";

// Render inside a <Link>: shows a shimmer while that link's page is loading.
export default function Pending() {
  const { pending } = useLinkStatus();
  return <span aria-hidden="true" className={`pending${pending ? " on" : ""}`} />;
}
