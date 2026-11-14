import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyCoupon } from '../src/coupons.js';

const NOW = new Date('2026-11-13T00:00:00Z');

test('a valid coupon takes its percentage off', () => {
  assert.equal(applyCoupon(10000, 'SAVE10', NOW), 9000);
});

test('an expired coupon leaves the total unchanged', () => {
  assert.equal(applyCoupon(10000, 'SPRING15', NOW), 10000);
});

test('codes are case-insensitive', () => {
  assert.equal(applyCoupon(10000, 'save10', NOW), 9000);
});

test('the discount is rounded to the nearest cent', () => {
  assert.equal(applyCoupon(999, 'SAVE10', NOW), 899);
});

test('an unknown code throws', () => {
  assert.throws(() => applyCoupon(100, 'NOPE', NOW), /Invalid coupon code: NOPE/);
});

test('a fractional or negative total is rejected', () => {
  assert.throws(() => applyCoupon(10.5, 'SAVE10', NOW), RangeError);
  assert.throws(() => applyCoupon(-1, 'SAVE10', NOW), RangeError);
});
