const COUPONS = {
  SAVE10: { percent: 10, expires: '2099-01-01' },
  SPRING15: { percent: 15, expires: '2026-06-01' },
};

/**
 * Apply a percentage coupon to a total in integer cents.
 * Codes are case-insensitive; an expired coupon leaves the total unchanged.
 */
export function applyCoupon(totalCents, code, now = new Date()) {
  if (!Number.isInteger(totalCents) || totalCents < 0) {
    throw new RangeError(`totalCents must be a non-negative integer, got ${totalCents}`);
  }
  const coupon = COUPONS[String(code).toUpperCase()];
  if (!coupon) throw new Error(`Invalid coupon code: ${code}`);
  if (now >= new Date(coupon.expires)) return totalCents;
  return totalCents - Math.round((totalCents * coupon.percent) / 100);
}
