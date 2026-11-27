"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

export default function Countdown({ initial, total }: { initial: number; total: number }) {
  const router = useRouter();
  const [left, setLeft] = useState(initial);

  useEffect(() => {
    const end = Date.now() + initial * 1000;
    const id = setInterval(() => {
      const s = Math.max(0, Math.ceil((end - Date.now()) / 1000));
      setLeft(s);
      if (s === 0) {
        clearInterval(id);
        router.refresh();
      }
    }, 1000);
    return () => clearInterval(id);
  }, [initial, router]);

  const mm = String(Math.floor(left / 60)).padStart(2, "0");
  const ss = String(left % 60).padStart(2, "0");

  return (
    <div role="timer" aria-live="off">
      <div className="timer">{mm}:{ss}</div>
      <div className="bar"><i style={{ width: `${Math.min(100, (left / total) * 100)}%` }} /></div>
    </div>
  );
}
