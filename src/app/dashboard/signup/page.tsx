"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { authClient } from "@/lib/auth-client";

export default function SignUp() {
  const router = useRouter();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setError(undefined);
    const f = new FormData(e.currentTarget);
    const { error } = await authClient.signUp.email({
      name: String(f.get("name")),
      email: String(f.get("email")),
      password: String(f.get("password")),
    });
    if (error) {
      setError(error.message ?? "Could not create account");
      setLoading(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <main className="mx-auto max-w-sm p-8">
      <h1 className="mb-6 text-2xl font-semibold">Create your account</h1>
      <form onSubmit={onSubmit} className="space-y-3">
        <input name="name" placeholder="Your name" required className="w-full rounded border p-2" />
        <input name="email" type="email" placeholder="Email" required className="w-full rounded border p-2" />
        <input name="password" type="password" placeholder="Password (8+ characters)" minLength={8} required className="w-full rounded border p-2" />
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button disabled={loading} className="w-full rounded bg-black p-2 text-white disabled:opacity-50">
          {loading ? "Creating..." : "Sign up"}
        </button>
      </form>
      <p className="mt-4 text-sm">Have an account? <Link href="/login" className="underline">Log in</Link></p>
    </main>
  );
}
