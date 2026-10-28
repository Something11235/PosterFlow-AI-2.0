// Four exact decimal places, represented as integer units for browser maths.
export const CREDIT_SCALE = 10000;
export function creditUnits(value) {
  if (typeof value !== "string" && typeof value !== "number") throw new Error("请输入有效积分。");
  const match = String(value).trim().match(/^(-?)(\d+)(?:\.(\d{1,4}))?$/);
  if (!match) throw new Error("积分最多保留四位小数。");
  const units = Number(match[2]) * CREDIT_SCALE + Number((match[3] || "").padEnd(4, "0"));
  if (!Number.isSafeInteger(units)) throw new Error("积分超出允许范围。");
  return match[1] ? -units : units;
}
export function creditText(value) {
  const units = creditUnits(value), absolute = Math.abs(units), whole = Math.floor(absolute / CREDIT_SCALE);
  const fraction = String(absolute % CREDIT_SCALE).padStart(4, "0").replace(/0+$/, "");
  return `${units < 0 ? "-" : ""}${whole}${fraction ? `.${fraction}` : ""}`;
}

export function displayCredits(value, empty = '—') {
  if (value == null) return empty;
  try { return creditText(value); } catch { return empty; }
}
