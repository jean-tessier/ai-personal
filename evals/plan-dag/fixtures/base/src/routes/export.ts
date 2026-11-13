import { Router } from "express";
import { db } from "../db.js";

export const exportRouter = Router();

// Full JSON dump of all tasks, used by the nightly backup job.
exportRouter.get("/", (_req, res) => {
  const rows = db.prepare("SELECT * FROM tasks ORDER BY id").all();
  res.setHeader("Content-Disposition", "attachment; filename=tasks.json");
  res.json(rows);
});
