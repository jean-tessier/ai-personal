import type { NewCustomer } from "../models/customer.js";

export class InvalidCustomerError extends Error {}

export function validateCustomer(customer: NewCustomer): void {
  if (!customer.name) throw new InvalidCustomerError("customer name is required");
  if (!/^[^@\s]+@[^@\s]+$/.test(customer.email)) throw new InvalidCustomerError("customer email is invalid");
  if (!["free", "pro"].includes(customer.plan)) throw new InvalidCustomerError("customer plan is invalid");
}
