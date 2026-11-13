import { listCustomers } from "../services/customerService.js";

// Monthly push of paying customers to the billing provider, keyed by customer id.
export async function syncPayingCustomers(): Promise<number> {
  const payingCustomers = listCustomers().filter((customer) => customer.plan === "pro");
  for (const customer of payingCustomers) {
    await fetch(`https://billing.example.invalid/v1/customers/${customer.id}`, {
      method: "PUT",
      body: JSON.stringify({ customerId: customer.id, email: customer.email }),
    });
  }
  return payingCustomers.length;
}
