import { Router } from "express";
import { db } from "../db.js";
import type { Task } from "../models/task.js";

export const tasksRouter = Router();

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

tasksRouter.get("/", (req, res) => {
  const size = Math.min(Number(req.query.size) || DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
  const page = Math.max(Number(req.query.page) || 1, 1);
  const rows = db
    .prepare("SELECT * FROM tasks ORDER BY id LIMIT ? OFFSET ?")
    .all(size, (page - 1) * size) as Task[];
  res.json({ page, size, items: rows });
});

tasksRouter.post("/", (req, res) => {
  const { title } = req.body as { title?: string };
  if (!title) return res.status(400).json({ error: "title is required" });
  const info = db.prepare("INSERT INTO tasks (title, done) VALUES (?, 0)").run(title);
  res.status(201).json({ id: info.lastInsertRowid, title, done: false });
});

tasksRouter.patch("/:id", (req, res) => {
  const { done } = req.body as { done?: boolean };
  db.prepare("UPDATE tasks SET done = ? WHERE id = ?").run(done ? 1 : 0, req.params.id);
  res.status(204).end();
});
