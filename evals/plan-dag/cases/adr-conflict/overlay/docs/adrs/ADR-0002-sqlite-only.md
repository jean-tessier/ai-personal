# ADR-0002: SQLite is the only datastore

- Status: Accepted
- Date: 2025-02-14

## Context
tasks-api runs as one process on one small VM. Every extra service is one more thing to patch, back up and page on.

## Decision
All data lives in one SQLite file. The app runs no external runtime services: no cache server, no separate
database server, no message broker. In-process caching is allowed.

## Consequences
Backups are a file copy. Scaling up means a bigger VM, not more instances.

## When to Reconsider
When we need to run more than one app instance, since a SQLite file cannot be shared across hosts.
