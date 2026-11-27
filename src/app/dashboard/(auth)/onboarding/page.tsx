import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import OnboardingForm from "./form";

export default async function Onboarding() {
  const session = await getSession();
  if (!session) redirect("/login");

  return (
    <div className="glass auth enter">
      <h1 className="display h-md">Set up your business</h1>
      <p className="muted">This creates your public booking page. You can add services and staff next.</p>
      <OnboardingForm rootDomain={process.env.NEXT_PUBLIC_ROOT_DOMAIN!} />
    </div>
  );
}
