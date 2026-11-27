import Link from "next/link";
import { notFound } from "next/navigation";
import { and, eq } from "drizzle-orm";
import { db } from "@/db";
import { services } from "@/db/schema";
import ActionForm from "@/components/action-form";
import { Chevron } from "@/components/icons";
import { requireTenant } from "@/lib/context";
import { num } from "@/lib/css";
import { isUuid } from "@/lib/ids";
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
    <>
      <Link href="/services" className="back enter" style={num(0)}>
        <Chevron /> Back to services
      </Link>
      <section className="glass panel enter" style={{ ...num(1), maxWidth: "36rem" }}>
        <h1 className="display h-md">Edit {service.name}</h1>
        <ActionForm action={updateService} submitLabel="Save changes">
          <ServiceFields service={service} />
        </ActionForm>
      </section>
    </>
  );
}
