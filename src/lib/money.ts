export const formatMoney = (pesewas: number) => `GH₵ ${(pesewas / 100).toFixed(2)}`;

export function depositLabel(type: string, value: number) {
  if (type === "fixed") return `${formatMoney(value)} deposit`;
  if (type === "percent") return `${value}% deposit`;
  return "No deposit";
}
