# ADR-0001: TypeScript on Node.js 22

- Status: Accepted
- Date: 2025-01-10

## Context
The team writes TypeScript daily and wants one runtime in development, CI and production.

## Decision
tasks-api is written in TypeScript (strict mode) and runs on Node.js 22 LTS.

## Consequences
CI and production pin Node.js 22. New code is TypeScript; no plain JavaScript files in `src/`.

## When to Reconsider
When Node.js 22 reaches end of life before we have upgraded.
