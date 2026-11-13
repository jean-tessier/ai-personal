import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { app } from "../src/app.js";

test("GET /export downloads every task as JSON", async () => {
  const res = await request(app).get("/export");
  assert.equal(res.status, 200);
  assert.match(res.headers["content-disposition"], /tasks\.json/);
});
