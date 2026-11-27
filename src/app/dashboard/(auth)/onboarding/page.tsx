import { redirect } from "next/navigation";
import { publicUrl } from "@/lib/context";
import { getSession } from "@/lib/session";
import OnboardingForm from "./form";

export default async function Onboarding() {
  const session = await getSession();
  if (!session) redirect("/login");

  const sample = await publicUrl("SLUG");
  const [prefix, suffix] = sample.replace(/^https?:\/\//, "").split("SLUG");

  return (
    <div className="glass auth enter">
      <h1 className="display h-md">Set up your business</h1>
      <p className="muted">This creates your public booking page. You can add services and staff next.</p>
      <OnboardingForm prefix={prefix} suffix={suffix} />
    </div>
  );
}
