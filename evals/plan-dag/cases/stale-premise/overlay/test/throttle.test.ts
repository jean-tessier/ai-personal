import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { app } from "../src/app.js";

test("the 101st request in a minute gets 429", async () => {
  for (let i = 0; i < 100; i++) await request(app).get("/tasks");
  const res = await request(app).get("/tasks");
  assert.equal(res.status, 429);
});
