import { listCustomers } from "../services/customerService.js";

// Nightly push of every customer to the CRM. The CRM's own field is called customer_ref.
export async function syncCustomersToCrm(): Promise<number> {
  const customers = listCustomers();
  for (const customer of customers) {
    await fetch("https://crm.example.invalid/api/customers", {
      method: "PUT",
      body: JSON.stringify({ customer_ref: customer.id, name: customer.name, email: customer.email }),
    });
  }
  return customers.length;
}
