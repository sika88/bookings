CREATE TYPE "public"."message_kind" AS ENUM('confirmation', 'reminder_24h', 'reminder_2h', 'cancellation');--> statement-breakpoint
CREATE TYPE "public"."message_status" AS ENUM('pending', 'sent', 'failed', 'skipped');--> statement-breakpoint
CREATE TABLE "messages" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"tenant_id" uuid NOT NULL,
	"booking_id" uuid NOT NULL,
	"kind" "message_kind" NOT NULL,
	"status" "message_status" DEFAULT 'pending' NOT NULL,
	"send_at" timestamp with time zone NOT NULL,
	"claimed_at" timestamp with time zone,
	"attempts" integer DEFAULT 0 NOT NULL,
	"last_error" text,
	"to_phone" text,
	"body" text,
	"provider_id" text,
	"sent_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "messages_booking_kind_uq" UNIQUE("booking_id","kind")
);
--> statement-breakpoint
ALTER TABLE "tenants" ADD COLUMN "sms_enabled" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_tenant_id_tenants_id_fk" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "messages" ADD CONSTRAINT "messages_booking_id_bookings_id_fk" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "messages_due_idx" ON "messages" USING btree ("status","send_at");--> statement-breakpoint
CREATE INDEX "messages_tenant_idx" ON "messages" USING btree ("tenant_id","created_at");