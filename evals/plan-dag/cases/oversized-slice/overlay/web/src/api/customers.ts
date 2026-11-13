import type { Customer } from "../../../src/models/customer";

export async function fetchCustomers(): Promise<Customer[]> {
  const res = await fetch("/customers");
  const body = (await res.json()) as { customers: Customer[] };
  return body.customers;
}

export async function fetchCustomer(customerId: number): Promise<Customer> {
  const res = await fetch(`/customers/${customerId}`);
  const body = (await res.json()) as { customer: Customer };
  return body.customer;
}
