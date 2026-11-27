"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { guessNetwork, NETWORKS, type Network } from "@/lib/networks";
import { checkPayment, payAction } from "./actions";
import type { PayState } from "./types";

export default function PayPanel({
  slug,
  token,
  amountLabel,
  defaultPhone,
  initial,
}: {
  slug: string;
  token: string;
  amountLabel: string;
  defaultPhone: string;
  initial: PayState;
}) {
  const router = useRouter();
  const [state, action, pending] = useActionState<PayState, FormData>(payAction, initial);
  const [local, setLocal] = useState<PayState>();
  const [phone, setPhone] = useState(defaultPhone);
  const [network, setNetwork] = useState<Network>(guessNetwork(defaultPhone) ?? "mtn");

  const view = local ?? state;
  const step = view.step;

  const submit = (fd: FormData) => {
    setLocal(undefined);
    action(fd);
  };

  useEffect(() => {
    if (step === "done") router.refresh();
  }, [step, router]);

  // while the customer approves on their phone, check for the result
  useEffect(() => {
    if (step !== "waiting") return;
    let live = true;
    const id = setInterval(async () => {
      const r = await checkPayment(slug, token);
      if (!live) return;
      if (r.outcome === "success" || r.outcome === "refund_due") {
        clearInterval(id);
        router.refresh();
      } else if (r.outcome === "failed" || r.outcome === "mismatch") {
        clearInterval(id);
        setLocal({ step: "failed", message: r.message ?? "The payment was not completed." });
      }
    }, 4000);
    return () => {
      live = false;
      clearInterval(id);
    };
  }, [step, slug, token, router]);

  const ids = (
    <>
      <input type="hidden" name="slug" value={slug} />
      <input type="hidden" name="token" value={token} />
    </>
  );

  if (view.step === "done") {
    return <p className="muted" role="status">Payment received. Confirming your booking...</p>;
  }

  if (view.step === "waiting") {
    return (
      <div className="wait" role="status" aria-live="polite">
        <span className="ring" aria-hidden="true" />
        <p className="display" style={{ fontSize: "1.25rem" }}>Waiting for your approval</p>
        <p className="muted">{view.message}</p>
        <p className="muted small">Approve the prompt and enter your PIN. This page updates by itself. You have about 3 minutes.</p>
        <form action={submit}>
          {ids}
          <input type="hidden" name="intent" value="reset" />
          <button className="linkbtn" disabled={pending}>Use a different number</button>
        </form>
      </div>
    );
  }

  if (view.step === "otp") {
    return (
      <form action={submit} className="form" style={{ marginTop: 0 }}>
        {ids}
        <input type="hidden" name="intent" value="otp" />
        <input type="hidden" name="reference" value={view.reference} />
        <p className="muted" role="status">{view.message}</p>
        <label>
          Code
          <input name="otp" required inputMode="numeric" autoComplete="one-time-code" className="field" />
        </label>
        <button disabled={pending} className="btn">{pending ? "Checking..." : "Confirm code"}</button>
      </form>
    );
  }

  if (view.step === "failed") {
    return (
      <div className="form" style={{ marginTop: 0 }}>
        <p className="alert" role="alert">{view.message}</p>
        <button type="button" className="btn" onClick={() => setLocal({ step: "form" })}>Try again</button>
      </div>
    );
  }

  return (
    <form action={submit} className="form" style={{ marginTop: 0 }}>
      {ids}
      <input type="hidden" name="intent" value="start" />
      <label>
        Mobile money number
        <input
          name="phone"
          type="tel"
          required
          autoComplete="tel"
          placeholder="024 123 4567"
          value={phone}
          onChange={(e) => {
            setPhone(e.target.value);
            const g = guessNetwork(e.target.value);
            if (g) setNetwork(g);
          }}
          className="field"
        />
      </label>
      <fieldset className="nets">
        <legend className="muted small" style={{ marginBottom: "0.5rem" }}>Network</legend>
        {(Object.keys(NETWORKS) as Network[]).map((code) => (
          <label key={code} className={`net${network === code ? " on" : ""}`}>
            <input type="radio" name="network" value={code} checked={network === code} onChange={() => setNetwork(code)} />
            {NETWORKS[code]}
          </label>
        ))}
      </fieldset>
      {view.error && <p className="alert" role="alert">{view.error}</p>}
      <button disabled={pending} className="btn">{pending ? "Sending prompt..." : `Pay ${amountLabel} with Mobile Money`}</button>
    </form>
  );
}
