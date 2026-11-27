export type BookingState =
  | {
      error?: string;
      values?: { name: string; phone: string; email: string; notes: string };
    }
  | undefined;
