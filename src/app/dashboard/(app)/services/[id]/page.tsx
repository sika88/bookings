import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import { requireTenant } from "@/lib/context";
import { isUuid } from "@/lib/ids";
import ActionForm from "@/components/action-form";
import { updateService } from "../actions";
import ServiceFields from "../fields";

export default async function EditService({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { tenant } = await requireTenant();
  if (!isUuid(id)) notFound();

  const [service] = await db
    .select()
    .from(services)
    .where(and(eq(services.id, id), eq(services.tenantId, tenant.id)))
    .limit(1);
  if (!service) notFound();

  return (
    <div className="space-y-6">
      <Link href="/services" className="text-sm underline">← Back to services</Link>
      <h1 className="text-2xl font-semibold">Edit service</h1>
      <ActionForm action={updateService} submitLabel="Save changes">
        <ServiceFields service={service} />
      </ActionForm>
    </div>
  );
}
