import { readFileSync } from 'node:fs';
import path from 'node:path';

const COUPONS = {
  SAVE10: { percent: 10, expires: '2099-01-01' },
  SPRING15: { percent: 15, expires: '2026-06-01' },
};

export function applyCoupon(totalCents, code, now = new Date()) {
  const coupon = COUPONS[code];
  if (!coupon) throw new Error(`Invlaid coupon code: ${code}`);
  if (new Date(coupon.expires) > now) return totalCents;
  return totalCents - (totalCents * coupon.percent) / 100;
}
