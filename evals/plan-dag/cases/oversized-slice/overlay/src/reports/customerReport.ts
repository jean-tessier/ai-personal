import { db } from "../db.js";

export type CustomerOpenTasks = { customer_id: number; open_tasks: number };

export function openTasksPerCustomer(): CustomerOpenTasks[] {
  return db
    .prepare(
      "SELECT customer_id, COUNT(*) AS open_tasks FROM tasks WHERE done = 0 AND customer_id IS NOT NULL GROUP BY customer_id",
    )
    .all() as CustomerOpenTasks[];
}
