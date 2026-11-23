import { z } from "zod";

const MONEY = /^\d+(\.\d{1,2})?$/;

const schema = z.object({
  name: z.string().trim().min(1, "Service name is required").max(80, "Name is too long"),
  description: z.string().trim().max(300, "Description is too long").optional(),
  durationMin: z.coerce.number().int("Duration must be a whole number").min(5, "Duration must be at least 5 minutes").max(720, "Duration is too long"),
  bufferMin: z.coerce.number().int("Buffer must be a whole number").min(0, "Buffer can't be negative").max(120, "Buffer is too long"),
  price: z.string().trim().regex(MONEY, "Enter a price like 50 or 50.00"),
  depositType: z.enum(["none", "fixed", "percent"]),
  deposit: z.string().trim().optional(),
});

export type ServiceInput = {
  name: string;
  description: string | null;
  durationMin: number;
  bufferMin: number;
  pricePesewas: number;
  depositType: "none" | "fixed" | "percent";
  depositValue: number;
};

export function parseService(formData: FormData): { error: string } | { data: ServiceInput } {
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const pricePesewas = Math.round(parseFloat(v.price) * 100);
  let depositValue = 0;

  if (v.depositType === "fixed") {
    if (!v.deposit || !MONEY.test(v.deposit)) return { error: "Enter the deposit amount, like 10 or 10.00" };
    depositValue = Math.round(parseFloat(v.deposit) * 100);
    if (depositValue <= 0) return { error: "The deposit must be more than 0" };
    if (depositValue > pricePesewas) return { error: "The deposit can't be more than the price" };
  } else if (v.depositType === "percent") {
    const n = Number(v.deposit);
    if (!Number.isInteger(n) || n < 1 || n > 100) return { error: "Deposit percentage must be a whole number from 1 to 100" };
    depositValue = n;
  }

  return {
    data: {
      name: v.name,
      description: v.description ? v.description : null,
      durationMin: v.durationMin,
      bufferMin: v.bufferMin,
      pricePesewas,
      depositType: v.depositType,
      depositValue,
    },
  };
}
