CREATE EXTENSION IF NOT EXISTS btree_gist;
--> statement-breakpoint
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_time_valid" CHECK ("ends_at" > "starts_at" AND "blocks_until" >= "ends_at");
--> statement-breakpoint
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_no_overlap" EXCLUDE USING gist ("staff_id" WITH =, tstzrange("starts_at", "blocks_until") WITH &&) WHERE ("status" IN ('pending', 'confirmed'));
