import { notFound } from "next/navigation";
import { getTenantBySlug } from "@/lib/tenant";

export default async function TenantHome({
  params,
}: {
  params: Promise<{ tenant: string }>;
}) {
  const { tenant: slug } = await params;
  const tenant = await getTenantBySlug(slug);
  if (!tenant) notFound();

  return (
    <main className="mx-auto max-w-2xl p-8">
      <h1 className="text-3xl font-semibold">{tenant.name}</h1>
      <p className="text-neutral-500">Booking page coming soon.</p>
    </main>
  );
}
