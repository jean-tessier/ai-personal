import { db } from "../db.js";
import type { Customer, CustomerId, NewCustomer } from "../models/customer.js";

export const customerRepository = {
  findCustomerById(id: CustomerId): Customer | undefined {
    return db.prepare("SELECT * FROM customers WHERE id = ?").get(id) as Customer | undefined;
  },
  listCustomers(): Customer[] {
    return db.prepare("SELECT * FROM customers ORDER BY id").all() as Customer[];
  },
  insertCustomer(customer: NewCustomer): CustomerId {
    const info = db
      .prepare("INSERT INTO customers (name, email, plan) VALUES (?, ?, ?)")
      .run(customer.name, customer.email, customer.plan);
    return Number(info.lastInsertRowid);
  },
  tasksForCustomer(customerId: CustomerId) {
    return db.prepare("SELECT * FROM tasks WHERE customer_id = ?").all(customerId);
  },
};
