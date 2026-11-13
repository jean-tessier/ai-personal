import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { app } from "../src/app.js";

test("POST /customers creates a customer", async () => {
  const res = await request(app).post("/customers").send({ name: "Acme", email: "ops@acme.example", plan: "pro" });
  assert.equal(res.status, 201);
  assert.equal(res.body.customer.name, "Acme");
});

test("GET /customers/:customerId returns 404 for an unknown customer", async () => {
  const res = await request(app).get("/customers/999999");
  assert.equal(res.status, 404);
});
