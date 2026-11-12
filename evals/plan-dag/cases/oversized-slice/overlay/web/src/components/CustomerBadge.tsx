import type { Customer } from "../../../src/models/customer";

export function CustomerBadge({ customer }: { customer: Customer }) {
  return <span className={`customer-badge customer-badge--${customer.plan}`}>{customer.plan}</span>;
}
