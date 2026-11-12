import { test } from "node:test";
import assert from "node:assert/strict";
import { customerRepository } from "../src/repositories/customerRepository.js";
import customers from "./fixtures/customers.json" with { type: "json" };

test("insertCustomer then findCustomerById round-trips a customer", () => {
  const customerId = customerRepository.insertCustomer(customers[0]);
  assert.equal(customerRepository.findCustomerById(customerId)?.email, customers[0].email);
});
