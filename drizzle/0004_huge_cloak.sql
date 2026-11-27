CREATE TYPE "public"."payment_status" AS ENUM('pending', 'success', 'failed', 'refund_due', 'mismatch');--> statement-breakpoint
CREATE TABLE "payments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"booking_id" uuid NOT NULL,
	"reference" text NOT NULL,
	"amount_pesewas" integer NOT NULL,
	"currency" text DEFAULT 'GHS' NOT NULL,
	"network" text NOT NULL,
	"phone" text NOT NULL,
	"status" "payment_status" DEFAULT 'pending' NOT NULL,
	"provider_status" text,
	"message" text,
	"raw" jsonb,
	"last_checked_at" timestamp with time zone,
	"paid_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "payments_reference_unique" UNIQUE("reference")
);
--> statement-breakpoint
CREATE TABLE "tenant_slug_history" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"slug" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tenant_slug_history_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_booking_id_bookings_id_fk" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tenant_slug_history" ADD CONSTRAINT "tenant_slug_history_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "payments_booking_idx" ON "payments" USING btree ("booking_id");--> statement-breakpoint
CREATE INDEX "payments_tenant_status_idx" ON "payments" USING btree ("tenant_id","status");--> statement-breakpoint
CREATE INDEX "slug_history_tenant_idx" ON "tenant_slug_history" USING btree ("tenant_id");