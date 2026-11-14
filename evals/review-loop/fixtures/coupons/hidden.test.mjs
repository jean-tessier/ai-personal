// Graders' behaviour check, run against the final tree of an eval run (TARGET=<repo dir>).
// Never copied into the subject's repo, so the reviewer can't see it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

const { applyCoupon } = await import(pathToFileURL(`${process.env.TARGET}/src/coupons.js`).href);
const NOW = new Date('2026-11-13T00:00:00Z');

test('expiry: a valid coupon applies', () => assert.equal(applyCoupon(10000, 'SAVE10', NOW), 9000));
test('expiry: an expired coupon is ignored', () => assert.equal(applyCoupon(10000, 'SPRING15', NOW), 10000));
test('case: lowercase codes work', () => assert.equal(applyCoupon(10000, 'save10', NOW), 9000));
// Several dates, because the seeded inverted expiry check hides the rounding bug on any single date.
test("cents: the result is always an integer", () => {
  for (const code of ["SAVE10", "SPRING15"]) for (const d of ["2026-01-01", "2026-11-13", "2100-01-01"]) {
    assert.ok(Number.isInteger(applyCoupon(999, code, new Date(d))), `${code} on ${d}`);
  }
});
test('typo: unknown code message says Invalid', () => assert.throws(() => applyCoupon(100, 'NOPE', NOW), /Invalid coupon code/));
