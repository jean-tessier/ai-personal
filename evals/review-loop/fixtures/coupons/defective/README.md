# shop

Tiny cart library. All amounts are integer cents.

## Cart

`subtotal(items)` returns the sum of `priceCents * qty` over the items.

## Coupons

`applyCoupon(totalCents, code, now = new Date())` applies a percentage coupon to a total.

- Codes are case-insensitive: `save10` works like `SAVE10`.
- An expired coupon leaves the total unchanged.
- An unknown code throws `Invalid coupon code: <code>`.
- The discount is rounded to the nearest cent.
