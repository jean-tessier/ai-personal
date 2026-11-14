import { test } from 'node:test';
import assert from 'node:assert/strict';
import { subtotal } from '../src/cart.js';

test('subtotal sums price times quantity', () => {
  assert.equal(subtotal([{ priceCents: 250, qty: 2 }, { priceCents: 100, qty: 1 }]), 600);
});

test('subtotal of an empty cart is 0', () => {
  assert.equal(subtotal([]), 0);
});
