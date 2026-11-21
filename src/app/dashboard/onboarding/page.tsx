import { redirect } from "next/navigation";
import { getSession } from "@/lib/session";
import OnboardingForm from "./form";

export default async function Onboarding() {
  const session = await getSession();
  if (!session) redirect("/login");

  return (
    <main className="mx-auto max-w-md p-8">
      <h1 className="mb-1 text-2xl font-semibold">Set up your business</h1>
      <p className="mb-6 text-sm text-neutral-500">This creates your public booking page.</p>
      <OnboardingForm rootDomain={process.env.NEXT_PUBLIC_ROOT_DOMAIN!} />
    </main>
  );
}
