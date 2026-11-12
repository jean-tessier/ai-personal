import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { app } from "../src/app.js";

test("POST /tasks rejects a missing title", async () => {
  const res = await request(app).post("/tasks").send({});
  assert.equal(res.status, 400);
});

test("GET /tasks returns a page", async () => {
  const res = await request(app).get("/tasks");
  assert.equal(res.status, 200);
  assert.ok(Array.isArray(res.body.items));
});
