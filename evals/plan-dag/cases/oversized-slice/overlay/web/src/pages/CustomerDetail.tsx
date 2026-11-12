import { useEffect, useState } from "react";
import type { Customer } from "../../../src/models/customer";
import { fetchCustomer } from "../api/customers";
import { CustomerBadge } from "../components/CustomerBadge";

export function CustomerDetail({ customerId }: { customerId: number }) {
  const [customer, setCustomer] = useState<Customer | null>(null);
  useEffect(() => {
    fetchCustomer(customerId).then(setCustomer);
  }, [customerId]);
  if (!customer) return <p>Loading customer…</p>;
  return (
    <article>
      <h1>
        {customer.name} <CustomerBadge customer={customer} />
      </h1>
      <p>Customer email: {customer.email}</p>
      <a href={`/customers/${customer.id}/tasks`}>Tasks for this customer</a>
    </article>
  );
}
