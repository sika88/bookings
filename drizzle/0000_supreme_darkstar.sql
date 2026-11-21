CREATE TYPE "public"."tenant_type" AS ENUM('salon', 'clinic', 'barber', 'venue');--> statement-breakpoint
CREATE TABLE "tenants" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	"type" "tenant_type" NOT NULL,
	"timezone" text DEFAULT 'Africa/Accra' NOT NULL,
	"currency" text DEFAULT 'GHS' NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tenants_slug_unique" UNIQUE("slug")
);
