CREATE TABLE invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  month TEXT NOT NULL,
  task_count INTEGER NOT NULL,
  amount_cents INTEGER NOT NULL,
  issued_at TEXT NOT NULL DEFAULT (datetime('now'))
);
