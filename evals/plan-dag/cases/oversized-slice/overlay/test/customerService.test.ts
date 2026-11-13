import { test } from "node:test";
import assert from "node:assert/strict";
import { createCustomer } from "../src/services/customerService.js";
import { InvalidCustomerError } from "../src/validation/customer.js";

test("createCustomer rejects an invalid customer email", () => {
  assert.throws(() => createCustomer({ name: "Acme", email: "nope", plan: "free" }), InvalidCustomerError);
});
