#!/usr/bin/env bash
# Builds the coupons fixture repo in the current directory: main = base, feature/coupons = base + the overlay.
#   bash evals/review-loop/scaffold.sh defective|clean
set -euo pipefail
FX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/coupons"
overlay="${1:?usage: scaffold.sh defective|clean}"
[ -d "$FX/$overlay" ] || { echo "scaffold.sh: no overlay '$overlay'" >&2; exit 64; }
git init -q -b main
git config user.name "Fixture Author"
git config user.email "fixture@example.invalid"
cp -R "$FX/base/." .
git add -A && git commit -q -m "feat: cart subtotal"
git switch -q -c feature/coupons
cp -R "$FX/$overlay/." .
git add -A && git commit -q -m "feat: add coupon codes"
