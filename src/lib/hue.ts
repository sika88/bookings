// Stable colour hue (0-359) from any string, used to theme each business.
export function hueOf(s: string) {
  let h = 7;
  for (const c of s) h = (h * 31 + c.charCodeAt(0)) % 360;
  return h;
}
