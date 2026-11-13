# ADR-0003: Ship tasks-api as a single deployable

- Status: Accepted
- Date: 2025-03-04

## Context
One team (tasks-core) builds and runs everything. Separate deployables would add release coordination for no gain.

## Decision
tasks-api, including billing, is built, versioned and deployed as one unit from this repository.

## Consequences
One pipeline, one version number, one rollback. Modules share the database and release together.

## When to Reconsider
When a second team owns a module, or a module needs its own release cadence.
