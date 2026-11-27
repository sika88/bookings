import type { ReactNode } from "react";
import { num } from "@/lib/css";

export default function PageHead({ title, sub, children }: { title: string; sub?: string; children?: ReactNode }) {
  return (
    <header className="page-head enter" style={num(0)}>
      <div>
        <h1 className="display">{title}</h1>
        {sub && <p className="muted">{sub}</p>}
      </div>
      {children}
    </header>
  );
}
