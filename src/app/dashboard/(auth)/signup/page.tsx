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
    <div className="glass auth enter">
      <h1 className="display h-md">Create your account</h1>
      <p className="muted">Set up online booking for your business in a few minutes.</p>
      <form onSubmit={onSubmit} className="form">
        <label>
          Your name
          <input name="name" required autoComplete="name" className="field" />
        </label>
        <label>
          Email
          <input name="email" type="email" required autoComplete="email" className="field" />
        </label>
        <label>
          Password
          <input name="password" type="password" minLength={8} required autoComplete="new-password" placeholder="At least 8 characters" className="field" />
        </label>
        {error && <p className="alert" role="alert">{error}</p>}
        <button disabled={loading} className="btn">{loading ? "Creating..." : "Sign up"}</button>
      </form>
      <p className="muted small" style={{ marginTop: "1.25rem" }}>
        Already have an account? <Link href="/login" className="link">Log in</Link>
      </p>
    </div>
  );
}
