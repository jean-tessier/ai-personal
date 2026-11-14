/** Sum of line items, in integer cents. */
export function subtotal(items) {
  return items.reduce((sum, { priceCents, qty }) => sum + priceCents * qty, 0);
}
