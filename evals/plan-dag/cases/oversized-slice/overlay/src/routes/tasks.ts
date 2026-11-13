import { Router } from "express";
import { db } from "../db.js";
import type { Task } from "../models/task.js";

export const tasksRouter = Router();

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

tasksRouter.get("/", (req, res) => {
  const size = Math.min(Number(req.query.size) || DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
  const page = Math.max(Number(req.query.page) || 1, 1);
  const customerId = req.query.customerId ? Number(req.query.customerId) : null;
  const rows = (
    customerId === null
      ? db.prepare("SELECT * FROM tasks ORDER BY id LIMIT ? OFFSET ?").all(size, (page - 1) * size)
      : db
          .prepare("SELECT * FROM tasks WHERE customer_id = ? ORDER BY id LIMIT ? OFFSET ?")
          .all(customerId, size, (page - 1) * size)
  ) as Task[];
  res.json({ page, size, items: rows });
});

tasksRouter.post("/", (req, res) => {
  const { title, customerId } = req.body as { title?: string; customerId?: number };
  if (!title) return res.status(400).json({ error: "title is required" });
  const info = db
    .prepare("INSERT INTO tasks (title, done, customer_id) VALUES (?, 0, ?)")
    .run(title, customerId ?? null);
  res.status(201).json({ id: info.lastInsertRowid, title, done: false, customerId: customerId ?? null });
});

tasksRouter.patch("/:id", (req, res) => {
  const { done } = req.body as { done?: boolean };
  db.prepare("UPDATE tasks SET done = ? WHERE id = ?").run(done ? 1 : 0, req.params.id);
  res.status(204).end();
});
