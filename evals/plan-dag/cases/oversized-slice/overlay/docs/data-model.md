# Data model

One SQLite file. Migrations in `db/migrations/` run in order at startup.

- `tasks`: id, title, done, created_at, customer_id (references customers.id)
- `customers`: id, name, email (unique), plan, created_at

The nightly backup copies the database file. The CRM and billing syncs read `customers` every night.
