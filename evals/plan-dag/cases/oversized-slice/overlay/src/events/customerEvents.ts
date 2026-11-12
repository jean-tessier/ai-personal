import { EventEmitter } from "node:events";
import type { Customer } from "../models/customer.js";

export const customerEvents = new EventEmitter();

export function emitCustomerCreated(customer: Customer): void {
  customerEvents.emit("customer.created", { customerId: customer.id, email: customer.email });
}
