import { db } from "../db.js";

export type Invoice = { id: number; taskCount: number; amountCents: number; issuedAt: string };

const CENTS_PER_TASK = 50;

// Bills a month of task usage. Reads the shared tasks table directly.
export function createInvoice(month: string): Invoice {
  const { n } = db
    .prepare("SELECT COUNT(*) AS n FROM tasks WHERE strftime('%Y-%m', created_at) = ?")
    .get(month) as { n: number };
  const info = db
    .prepare("INSERT INTO invoices (month, task_count, amount_cents) VALUES (?, ?, ?)")
    .run(month, n, n * CENTS_PER_TASK);
  return {
    id: Number(info.lastInsertRowid),
    taskCount: n,
    amountCents: n * CENTS_PER_TASK,
    issuedAt: new Date().toISOString(),
  };
}
