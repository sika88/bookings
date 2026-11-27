"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { authClient } from "@/lib/auth-client";

export default function Login() {
  const router = useRouter();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setError(undefined);
    const f = new FormData(e.currentTarget);
    const { error } = await authClient.signIn.email({
      email: String(f.get("email")),
      password: String(f.get("password")),
    });
    if (error) {
      setError(error.message ?? "Invalid email or password");
      setLoading(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <div className="glass auth enter">
      <h1 className="display h-md">Welcome back</h1>
      <p className="muted">Log in to manage your bookings.</p>
      <form onSubmit={onSubmit} className="form">
        <label>
          Email
          <input name="email" type="email" required autoComplete="email" className="field" />
        </label>
        <label>
          Password
          <input name="password" type="password" required autoComplete="current-password" className="field" />
        </label>
        {error && <p className="alert" role="alert">{error}</p>}
        <button disabled={loading} className="btn">{loading ? "Logging in..." : "Log in"}</button>
      </form>
      <p className="muted small" style={{ marginTop: "1.25rem" }}>
        New here? <Link href="/signup" className="link">Create an account</Link>
      </p>
    </div>
  );
}
