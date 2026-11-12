import { customerRepository } from "../repositories/customerRepository.js";
import type { Customer, NewCustomer } from "../models/customer.js";
import { validateCustomer } from "../validation/customer.js";
import { emitCustomerCreated } from "../events/customerEvents.js";

export function createCustomer(input: NewCustomer): Customer {
  validateCustomer(input);
  const customerId = customerRepository.insertCustomer(input);
  const customer = customerRepository.findCustomerById(customerId)!;
  emitCustomerCreated(customer);
  return customer;
}

export function getCustomer(customerId: number): Customer | undefined {
  return customerRepository.findCustomerById(customerId);
}

export function listCustomers(): Customer[] {
  return customerRepository.listCustomers();
}
