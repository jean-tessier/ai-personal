import { useEffect, useState } from "react";
import type { Customer } from "../../../src/models/customer";
import { fetchCustomers } from "../api/customers";
import { CustomerBadge } from "../components/CustomerBadge";

export function CustomerList() {
  const [customers, setCustomers] = useState<Customer[]>([]);
  useEffect(() => {
    fetchCustomers().then(setCustomers);
  }, []);
  return (
    <section>
      <h1>Customers</h1>
      <ul>
        {customers.map((customer) => (
          <li key={customer.id}>
            <a href={`/customers/${customer.id}`}>{customer.name}</a> <CustomerBadge customer={customer} />
          </li>
        ))}
      </ul>
    </section>
  );
}
